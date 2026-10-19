-- Femboy drop: удача игрока (1 = обычные шансы)
alter table public.fd_players add column if not exists luck numeric not null default 1 check (luck between 0.2 and 5);

create or replace function public.fd_open_many(p_case text, p_n int) returns json language plpgsql security definer set search_path=public as $$
declare u uuid:=auth.uid(); c fd_cases; L numeric; tot numeric; r numeric; it record; pick text; b bigint; inv bigint; v int; res json[]:='{}'; best_v int:=0; k int; vmin numeric;
begin
  if p_n<1 or p_n>5 then raise exception 'Можно открыть от 1 до 5 кейсов'; end if;
  select * into c from fd_cases where id=p_case; if c.id is null then raise exception 'Нет такого кейса'; end if;
  update fd_players set balance=balance-c.price*p_n,opened=opened+p_n where id=u and balance>=c.price*p_n returning balance, luck into b, L;
  if b is null then raise exception 'Не хватает монет'; end if;
  select min(i.value) into vmin from fd_case_items ci join fd_items i on i.id=ci.item_id where ci.case_id=p_case;
  -- удача увеличивает вес дорогих скинов: вес * (цена/самый дешёвый)^(удача-1)/2
  select sum(ci.weight*power(i.value/vmin,(L-1)/2)) into tot from fd_case_items ci join fd_items i on i.id=ci.item_id where ci.case_id=p_case;
  for k in 1..p_n loop
    pick:=null; r:=random()*tot;
    for it in select ci.item_id, ci.weight*power(i.value/vmin,(L-1)/2) w from fd_case_items ci join fd_items i on i.id=ci.item_id where ci.case_id=p_case order by ci.item_id loop
      r:=r-it.w; if r<0 then pick:=it.item_id; exit; end if;
    end loop;
    if pick is null then select item_id into pick from fd_case_items where case_id=p_case limit 1; end if;
    insert into fd_inventory(user_id,item_id) values(u,pick) returning id into inv;
    select value into v from fd_items where id=pick; best_v:=greatest(best_v,v);
    res:=res||json_build_object('item',pick,'inv',inv);
  end loop;
  update fd_players set best=greatest(best,best_v) where id=u;
  return json_build_object('drops',array_to_json(res),'balance',b);
end $$;

create or replace function public.fd_open(p_case text) returns json language plpgsql security definer set search_path=public as $$
declare r json;
begin r:=fd_open_many(p_case,1); return json_build_object('item',r->'drops'->0->>'item','inv',(r->'drops'->0->>'inv')::bigint,'balance',(r->>'balance')::bigint); end $$;

create or replace function public.fd_upgrade_many(p_invs bigint[], p_target text) returns json language plpgsql security definer set search_path=public as $$
declare u uuid:=auth.uid(); fv bigint; n int; tv int; ch numeric; real_ch numeric; roll numeric; win boolean; newinv bigint; comp text; compinv bigint; L numeric;
begin
  if coalesce(array_length(p_invs,1),0)<1 or array_length(p_invs,1)>10 then raise exception 'Выбери от 1 до 10 скинов'; end if;
  select coalesce(sum(i.value),0), count(*) into fv, n from fd_inventory v join fd_items i on i.id=v.item_id where v.id=any(p_invs) and v.user_id=u;
  if n<>(select count(distinct x) from unnest(p_invs) x) then raise exception 'Предмет не найден'; end if;
  select value into tv from fd_items where id=p_target;
  if tv is null or tv<=fv then raise exception 'Цель должна быть дороже'; end if;
  select luck into L from fd_players where id=u;
  ch:=least(0.95, fv::numeric/tv);
  real_ch:=least(0.97, ch*coalesce(L,1));
  roll:=random(); win:=roll<real_ch;
  -- стрелка останавливается в нужной зоне колеса
  if win then roll:=random()*ch*0.96+ch*0.02; else roll:=ch+random()*(1-ch)*0.96+(1-ch)*0.02; end if;
  delete from fd_inventory where id=any(p_invs) and user_id=u;
  update fd_players set ups=ups+1, up_wins=up_wins+(case when win then 1 else 0 end), best=case when win then greatest(best,tv) else best end where id=u;
  if win then
    insert into fd_inventory(user_id,item_id) values(u,p_target) returning id into newinv;
  else
    select id into comp from fd_items where value<=fv*0.07 order by random()*value desc limit 1;
    if comp is not null then insert into fd_inventory(user_id,item_id) values(u,comp) returning id into compinv; end if;
  end if;
  return json_build_object('win',win,'roll',roll,'chance',ch,'inv',newinv,'comp_item',comp,'comp_inv',compinv);
end $$;

-- админка: поиск с удачей и изменение удачи
drop function if exists public.fd_admin_find(text);
create function public.fd_admin_find(q text) returns table(id uuid, username text, email text, balance bigint, luck numeric) language plpgsql security definer set search_path=public as $$
begin
  if not fd_is_admin() then raise exception 'Нет доступа'; end if;
  return query select p.id,p.username,u.email::text,p.balance,p.luck from fd_players p join auth.users u on u.id=p.id
    where q='' or p.username ilike '%'||q||'%' or u.email ilike '%'||q||'%' order by p.created_at desc limit 50;
end $$;
create or replace function public.fd_admin_luck(p_user uuid, p_luck numeric) returns numeric language plpgsql security definer set search_path=public as $$
begin
  if not fd_is_admin() then raise exception 'Нет доступа'; end if;
  update fd_players set luck=greatest(0.2,least(5,p_luck)) where id=p_user;
  return (select luck from fd_players where id=p_user);
end $$;
revoke execute on function public.fd_open(text), public.fd_admin_find(text), public.fd_admin_luck(uuid,numeric) from public, anon;
grant execute on function public.fd_open(text), public.fd_admin_find(text), public.fd_admin_luck(uuid,numeric) to authenticated;

-- тебе удача x2
update public.fd_players set luck=2 where id=(select id from auth.users where email='wiynet@gmail.com');
