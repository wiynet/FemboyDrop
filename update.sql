-- Femboy drop: цены как в КС + пересчёт редкости и цен кейсов
update public.fd_items i set value=greatest(3,round(v.usd*150)) from (values
('AWP','Safari Mesh',0.1),('AWP','Pink DDPAT',6),('AWP','Worm God',1),('AWP','Atheris',2),('AWP','Electric Hive',10),('AWP','Hyper Beast',20),('AWP','Asiimov',100),('AWP','Neo-Noir',15),('AWP','Lightning Strike',300),('AWP','Gungnir',10000),('AWP','Dragon Lore',12000),
('AK-47','Safari Mesh',0.1),('AK-47','Slate',3),('AK-47','Elite Build',1),('AK-47','Frontside Misty',15),('AK-47','Point Disarray',12),('AK-47','Neon Rider',40),('AK-47','Redline',25),('AK-47','Vulcan',150),('AK-47','Fire Serpent',800),('AK-47','Wild Lotus',9000),
('★ Karambit','Night',700),('★ Karambit','Tiger Tooth',1200),('★ Karambit','Fade',1800),('★ Karambit','Lore',1500),('★ Karambit','Doppler Black Pearl',4500),('★ Karambit','Doppler Ruby',5500),('★ Karambit','Doppler Sapphire',8000),
('M4A4','Urban DDPAT',0.1),('M4A4','Evil Daimyo',2),('M4A4','Cyber Security',10),('M4A4','Desolate Space',10),('M4A4','Buzz Kill',8),('M4A4','Asiimov',100),('M4A4','Howl',4500),
('Desert Eagle','Mudder',0.1),('Desert Eagle','Conspiracy',1),('Desert Eagle','Ocean Drive',20),('Desert Eagle','Code Red',50),('Desert Eagle','Printstream',50),('Desert Eagle','Blaze',600),
('USP-S','Forest Leaves',0.1),('USP-S','Blueprint',1),('USP-S','Cortex',4),('USP-S','Orion',10),('USP-S','Kill Confirmed',60),
('FAMAS','Colony',0.05),('FAMAS','Mecha Industries',1),('FAMAS','Eye of Athena',2),('FAMAS','Roll Cage',3),('FAMAS','Commemoration',40),
('★ Hand Wraps','Cobalt Skulls',250),('★ Moto Gloves','Spearmint',500),('★ Driver Gloves','King Snake',900),('★ Specialist Gloves','Crimson Kimono',3000),('★ Sport Gloves','Vice',2500),('★ Sport Gloves','Pandora''s Box',9000),
('M4A1-S','Boreal Forest',0.1),('M4A1-S','Decimator',3),('M4A1-S','Hyper Beast',15),('M4A1-S','Printstream',120),('M4A1-S','Hot Rod',400),
('★ Butterfly Knife','Safari Mesh',700),('★ Butterfly Knife','Crimson Web',1500),('★ Butterfly Knife','Marble Fade',2500),('★ Butterfly Knife','Fade',3000),('★ Butterfly Knife','Gamma Doppler Emerald',9000),
('P250','Sand Dune',0.03),('P250','Supernova',0.5),('P250','Muertos',2),('P250','See Ya Later',6),
('MP5-SD','Dirt Drop',0.03),('MP5-SD','Lab Rats',1),('MP5-SD','Phosphor',2),('MP5-SD','Liquidation',1.5),
('Glock-18','Groundwater',0.05),('Glock-18','Candy Apple',2),('Glock-18','Water Elemental',5),('Glock-18','Fade',1500),
('MP7','Skulls',3),('MP7','Nemesis',3.5),('MP7','Bloodsport',5),
('AUG','Storm',0.05),('AUG','Chameleon',2),('AUG','Akihabara Accept',400),
('Galil AR','Sage Spray',0.03),('Galil AR','Eco',2),('Galil AR','Chatterbox',30),
('MAC-10','Candy Apple',0.5),('MAC-10','Disco Tech',3),('MAC-10','Neon Rider',5),
('P90','Trigon',4),('P90','Death by Kitty',80),('P90','Asiimov',10),
('SG 553','Pulse',0.5),('SG 553','Cyrex',2),('SG 553','Integrale',100),
('SSG 08','Acid Fade',10),('SSG 08','Blood in the Water',40),('SSG 08','Dragonfire',50),
('Tec-9','Toxic',2),('Tec-9','Fuel Injector',15),('Tec-9','Nuclear Threat',300),
('UMP-45','Carbon Fiber',0.05),('UMP-45','Primal Saber',5),('UMP-45','Blaze',20),
('★ M9 Bayonet','Crimson Web',900),('★ M9 Bayonet','Marble Fade',2000),('★ M9 Bayonet','Lore',2200),
('Five-SeveN','Monkey Business',4),('Five-SeveN','Hyper Beast',10)
) as v(w,s,usd) where i.weapon=v.w and i.skin=v.s;

update public.fd_items set rarity=case when weapon like '★%' then 6 when value>=15000 then 5 when value>=3000 then 4 when value>=600 then 3 when value>=150 then 2 when value>=30 then 1 else 0 end;

update public.fd_cases c set price=greatest(5, case when x.p<100 then round(x.p) when x.p<1000 then round(x.p,-1) when x.p<100000 then round(x.p,-2) else round(x.p,-3) end)
from (select ci.case_id, sum(ci.weight*i.value)/sum(ci.weight)/0.85 p from fd_case_items ci join fd_items i on i.id=ci.item_id group by ci.case_id) x where c.id=x.case_id;
