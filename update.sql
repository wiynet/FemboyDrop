-- Femboy drop: живая лента, статистика, апгрейд с балансом
create or replace function public.fd_recent() returns table(id bigint, item_id text, username text) language sql stable security definer set search_path=public as $$
  select v.id, v.item_id, p.username from fd_inventory v join fd_players p on p.id=v.user_id order by v.id desc limit 24
$$;
create or replace function public.fd_stats() returns json language sql stable security definer set search_path=public as $$
  select json_build_object('players',(select count(*) from fd_players),'ups',(select coalesce(sum(ups),0) from fd_players))
$$;
grant execute on function public.fd_recent(), public.fd_stats() to anon, authenticated;

create or replace function public.fd_upgrade_bal(p_invs bigint[], p_bal bigint, p_target text) returns json language plpgsql security definer set search_path=public as $$
declare u uuid:=auth.uid(); fv bigint:=0; n int:=0; tv bigint; ch numeric; real_ch numeric; roll numeric; win boolean; newinv bigint; comp text; compinv bigint; L numeric; b bigint;
begin
  p_invs:=coalesce(p_invs,'{}'); p_bal:=coalesce(p_bal,0);
  if p_bal<0 then raise exception 'Неверная сумма'; end if;
  if cardinality(p_invs)>10 then raise exception 'Можно выбрать до 10 скинов'; end if;
  if cardinality(p_invs)=0 and p_bal=0 then raise exception 'Выбери скины или сумму баланса'; end if;
  if cardinality(p_invs)>0 then
    select coalesce(sum(i.value),0), count(*) into fv, n from fd_inventory v join fd_items i on i.id=v.item_id where v.id=any(p_invs) and v.user_id=u;
    if n<>(select count(distinct x) from unnest(p_invs) x) then raise exception 'Предмет не найден'; end if;
  end if;
  update fd_players set balance=balance-p_bal where id=u and balance>=p_bal returning balance, luck into b, L;
  if b is null then raise exception 'Не хватает монет'; end if;
  fv:=fv+p_bal;
  select value into tv from fd_items where id=p_target;
  if tv is null or tv<=fv then raise exception 'Цель должна быть дороже'; end if;
  ch:=least(0.95, fv::numeric/tv);
  real_ch:=least(0.97, ch*coalesce(L,1));
  win:=random()<real_ch;
  if win then roll:=random()*ch*0.96+ch*0.02; else roll:=ch+random()*(1-ch)*0.96+(1-ch)*0.02; end if;
  if cardinality(p_invs)>0 then delete from fd_inventory where id=any(p_invs) and user_id=u; end if;
  update fd_players set ups=ups+1, up_wins=up_wins+(case when win then 1 else 0 end), best=case when win then greatest(best,tv) else best end where id=u;
  if win then
    insert into fd_inventory(user_id,item_id) values(u,p_target) returning id into newinv;
  else
    select id into comp from fd_items where value<=fv*0.07 order by random()*value desc limit 1;
    if comp is not null then insert into fd_inventory(user_id,item_id) values(u,comp) returning id into compinv; end if;
  end if;
  return json_build_object('win',win,'roll',roll,'chance',ch,'inv',newinv,'comp_item',comp,'comp_inv',compinv,'balance',b);
end $$;
revoke execute on function public.fd_upgrade_bal(bigint[],bigint,text) from public, anon;
grant execute on function public.fd_upgrade_bal(bigint[],bigint,text) to authenticated;
