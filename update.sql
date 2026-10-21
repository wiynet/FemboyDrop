-- Femboy drop: исправления багов (можно запускать повторно)
-- 1) апгрейд: скины сначала удаляются, потом считается шанс — два одновременных запроса больше не дают дюп
-- 2) открытие пустого кейса даёт понятную ошибку
-- 3) живая лента, статистика и апгрейд с балансом (если ещё не были созданы)

create or replace function public.fd_recent() returns table(id bigint, item_id text, username text) language sql stable security definer set search_path=public as $$
  select v.id, v.item_id, p.username from fd_inventory v join fd_players p on p.id=v.user_id order by v.id desc limit 24
$$;
create or replace function public.fd_stats() returns json language sql stable security definer set search_path=public as $$
  select json_build_object('players',(select count(*) from fd_players),'ups',(select coalesce(sum(ups),0) from fd_players))
$$;
grant execute on function public.fd_recent(), public.fd_stats() to anon, authenticated;

create or replace function public.fd_open_many(p_case text, p_n int) returns json language plpgsql security definer set search_path=public as $$
declare u uuid:=auth.uid(); c fd_cases; L numeric; tot numeric; r numeric; it record; pick text; b bigint; inv bigint; v int; res json[]:='{}'; best_v int:=0; k int; vmin numeric;
begin
  if u is null then raise exception 'Нужно войти'; end if;
  if p_n is null or p_n<1 or p_n>5 then raise exception 'Можно открыть от 1 до 5 кейсов'; end if;
  select * into c from fd_cases where id=p_case; if c.id is null then raise exception 'Нет такого кейса'; end if;
  select min(i.value) into vmin from fd_case_items ci join fd_items i on i.id=ci.item_id where ci.case_id=p_case and ci.weight>0;
  if vmin is null then raise exception 'Кейс пуст'; end if;
  vmin:=greatest(vmin,1);
  update fd_players set balance=balance-c.price*p_n,opened=opened+p_n where id=u and balance>=c.price*p_n returning balance, luck into b, L;
  if b is null then raise exception 'Не хватает монет'; end if;
  L:=coalesce(L,1);
  -- удача увеличивает вес дорогих скинов: вес * (цена/самый дешёвый)^(удача-1)/2
  select sum(ci.weight*power(greatest(i.value,1)/vmin,(L-1)/2)) into tot from fd_case_items ci join fd_items i on i.id=ci.item_id where ci.case_id=p_case and ci.weight>0;
  for k in 1..p_n loop
    pick:=null; r:=random()*tot;
    for it in select ci.item_id, ci.weight*power(greatest(i.value,1)/vmin,(L-1)/2) w from fd_case_items ci join fd_items i on i.id=ci.item_id where ci.case_id=p_case and ci.weight>0 order by ci.item_id loop
      pick:=it.item_id; r:=r-it.w; if r<0 then exit; end if;
    end loop;
    insert into fd_inventory(user_id,item_id) values(u,pick) returning id into inv;
    select value into v from fd_items where id=pick; best_v:=greatest(best_v,v);
    res:=res||json_build_object('item',pick,'inv',inv);
  end loop;
  update fd_players set best=greatest(best,best_v) where id=u;
  return json_build_object('drops',array_to_json(res),'balance',b);
end $$;

create or replace function public.fd_upgrade_bal(p_invs bigint[], p_bal bigint, p_target text) returns json language plpgsql security definer set search_path=public as $$
declare u uuid:=auth.uid(); fv bigint:=0; n int:=0; want int; tv bigint; ch numeric; real_ch numeric; roll numeric; win boolean; newinv bigint; comp text; compinv bigint; L numeric; b bigint;
begin
  if u is null then raise exception 'Нужно войти'; end if;
  p_invs:=coalesce(p_invs,'{}'); p_bal:=coalesce(p_bal,0);
  if p_bal<0 then raise exception 'Неверная сумма'; end if;
  want:=(select count(distinct x) from unnest(p_invs) x where x is not null);
  if want>10 then raise exception 'Можно выбрать до 10 скинов'; end if;
  if want=0 and p_bal=0 then raise exception 'Выбери скины или сумму баланса'; end if;
  select value into tv from fd_items where id=p_target;
  if tv is null then raise exception 'Нет такого скина'; end if;
  -- удаляем сразу: параллельный запрос с теми же скинами их уже не найдёт
  if want>0 then
    with d as (delete from fd_inventory v where v.id=any(p_invs) and v.user_id=u returning v.item_id)
    select coalesce(sum(i.value),0), count(*) into fv, n from d join fd_items i on i.id=d.item_id;
    if n<>want then raise exception 'Предмет не найден'; end if;
  end if;
  update fd_players set balance=balance-p_bal, ups=ups+1 where id=u and balance>=p_bal returning balance, luck into b, L;
  if b is null then raise exception 'Не хватает монет'; end if;
  fv:=fv+p_bal;
  if tv<=fv then raise exception 'Цель должна быть дороже'; end if;
  ch:=least(0.95, fv::numeric/tv);
  real_ch:=least(0.97, ch*coalesce(L,1));
  win:=random()<real_ch;
  -- стрелка останавливается в нужной зоне колеса
  if win then roll:=random()*ch*0.96+ch*0.02; else roll:=ch+random()*(1-ch)*0.96+(1-ch)*0.02; end if;
  if win then
    update fd_players set up_wins=up_wins+1, best=greatest(best,tv) where id=u;
    insert into fd_inventory(user_id,item_id) values(u,p_target) returning id into newinv;
  else
    select id into comp from fd_items where value<=fv*0.07 order by random()*value desc limit 1;
    if comp is not null then insert into fd_inventory(user_id,item_id) values(u,comp) returning id into compinv; end if;
  end if;
  return json_build_object('win',win,'roll',roll,'chance',ch,'inv',newinv,'comp_item',comp,'comp_inv',compinv,'balance',b);
end $$;
revoke execute on function public.fd_upgrade_bal(bigint[],bigint,text) from public, anon;
grant execute on function public.fd_upgrade_bal(bigint[],bigint,text) to authenticated;

-- старые функции апгрейда работают через новую
create or replace function public.fd_upgrade_many(p_invs bigint[], p_target text) returns json language plpgsql security definer set search_path=public as $$
begin
  if coalesce(cardinality(p_invs),0)<1 then raise exception 'Выбери от 1 до 10 скинов'; end if;
  return fd_upgrade_bal(p_invs, 0, p_target);
end $$;
revoke execute on function public.fd_upgrade_many(bigint[],text) from public, anon;
grant execute on function public.fd_upgrade_many(bigint[],text) to authenticated;

create or replace function public.fd_upgrade(p_inv bigint, p_target text) returns json language sql security definer set search_path=public as $$
  select public.fd_upgrade_many(array[p_inv], p_target)
$$;
revoke execute on function public.fd_upgrade(bigint,text) from public, anon;
grant execute on function public.fd_upgrade(bigint,text) to authenticated;
