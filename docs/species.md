# Ресурсы видов

Техническая справка для изменения ресурсов и кода. Для первого знакомства: [прогулка](guide.md), [описание моделей](models.md).

All **29** plants are plain `ForestPlantDefinition` resources in `data/plants/`,
listed in `data/forest.tres`. They use one model and mesh builder. Repeated geometric
modules (including generic rotated whorls for pinnate fern fronds) contain no species-ID branches.
Each resource links to a Kew POWO name search. These links document the taxonomic names.
The 20 new resources can be reproduced with `python tools/generate_regional_plants.py`.

| Resource | Russian name | Latin name | Growth form | Mycorrhiza trait | Diaspore |
| --- | --- | --- | --- | --- | --- |
| `spruce.tres` | Ель обыкновенная | *Picea abies* | tree | ecto | seed |
| `birch.tres` | Берёза повислая | *Betula pendula* | tree | ecto | seed |
| `aspen.tres` | Осина | *Populus tremula* | tree | ecto | seed |
| `grey_willow.tres` | Ива пепельная | *Salix cinerea* | shrub | ecto | seed |
| `raspberry.tres` | Малина обыкновенная | *Rubus idaeus* | shrub | arbuscular | seed |
| `bilberry.tres` | Черника обыкновенная | *Vaccinium myrtillus* | dwarf_shrub | ericoid | seed |
| `wood_sorrel.tres` | Кислица обыкновенная | *Oxalis acetosella* | herb | arbuscular | seed |
| `tufted_hairgrass.tres` | Щучка дернистая | *Deschampsia cespitosa* | grass | arbuscular | seed |
| `balsam.tres` | Недотрога обыкновенная | *Impatiens noli-tangere* | herb | arbuscular | seed |
| `rowan.tres` | Рябина обыкновенная | *Sorbus aucuparia* | tree | arbuscular | seed |
| `oak.tres` | Дуб черешчатый | *Quercus robur* | tree | ecto | seed |
| `lime.tres` | Липа мелколистная | *Tilia cordata* | tree | ecto | seed |
| `maple.tres` | Клён остролистный | *Acer platanoides* | tree | arbuscular | seed |
| `black_alder.tres` | Ольха чёрная | *Alnus glutinosa* | tree | ecto | seed |
| `pine.tres` | Сосна обыкновенная | *Pinus sylvestris* | tree | ecto | seed |
| `bird_cherry.tres` | Черёмуха обыкновенная | *Prunus padus* | tree | arbuscular | seed |
| `hazel.tres` | Лещина обыкновенная | *Corylus avellana* | shrub | ecto | seed |
| `guelder_rose.tres` | Калина обыкновенная | *Viburnum opulus* | shrub | arbuscular | seed |
| `alder_buckthorn.tres` | Крушина ломкая | *Frangula alnus* | shrub | arbuscular | seed |
| `fly_honeysuckle.tres` | Жимолость лесная | *Lonicera xylosteum* | shrub | arbuscular | seed |
| `juniper.tres` | Можжевельник обыкновенный | *Juniperus communis* | shrub | arbuscular | seed |
| `lingonberry.tres` | Брусника | *Vaccinium vitis-idaea* | dwarf_shrub | ericoid | seed |
| `heather.tres` | Вереск обыкновенный | *Calluna vulgaris* | dwarf_shrub | ericoid | seed |
| `male_fern.tres` | Щитовник мужской | *Dryopteris filix-mas* | herb | arbuscular | spore |
| `ostrich_fern.tres` | Страусник обыкновенный | *Matteuccia struthiopteris* | herb | arbuscular | spore |
| `bracken.tres` | Орляк обыкновенный | *Pteridium aquilinum* | herb | arbuscular | spore |
| `wood_anemone.tres` | Ветреница дубравная | *Anemone nemorosa* | herb | arbuscular | seed |
| `lily_of_valley.tres` | Ландыш майский | *Convallaria majalis* | herb | arbuscular | seed |
| `meadowsweet.tres` | Таволга вязолистная | *Filipendula ulmaria* | herb | arbuscular | seed |

## Scenario parameters

The numeric fields (`biomass_kg_c`, `cn_ratio`, `cp_ratio`, `height_growth_m_year`,
`transpiration_m_s`, `seed_cost_kg_c`, `reproduction_per_year`, `dispersal_m`,
`germination_fraction`, `recruitment_light`, `dead_decay_per_year`, and the flood/stress values) are **qualitative
scenario assumptions**. They give the life forms different growth, resource use and stress
responses. `biomass_kg_c` is the reference carbon reserve at `size = 1`.
The source links document taxonomic names and life forms. Field calibration remains open.

`edible_fraction` is a conservative positive browse share for hare on a few understory sources
(grey willow, raspberry, bilberry, wood sorrel, tufted hairgrass).
Toxicity and food safety lie outside this model.

Initial placement normalizes species weights over the same 4,600 placement attempts;
the shipped seed initially accepts 3,482 individuals across the species mix.
Placement follows the scenario habitat rules.

## Connected processes and limits

`leaf_mass_fraction` marks carbon already inside live biomass. Deciduous leaf loss
transfers its C/N/P to local soil.
Evergreen needle turnover is not yet modeled. `mycorrhiza_type = ecto` permits paid
local exchange with ECM fungal patches. `arbuscular` and `ericoid` are stored as metadata;
their exchange channels await implementation. No nitrogen fixation is implemented for alder.

The three ferns have `propagule_kind = spore`; they share the finite diaspore ledger
and recruitment code. The model does not resolve gametophytes, fertilization, or
vegetative rhizome spread. The shapes and berries use procedural visual recipes.

Fungi are resource definitions too: meadow mushroom (*Marasmius oreades*, saprotroph),
porcini (*Boletus edulis*, ECM), and chanterelle (*Cantharellus cibarius*, ECM). They have
different cap/stem geometry and representative fruit mass/lifetime. Their spatial
kinetics and exchange coefficients are scenario parameters.
See [tests, mechanism and sources](../verification/2026-10-31-ecosystem.md).

## Perennial clones and shoot age

A perennial genet can persist for many years while its shoots or ramets die and regrow. Raspberry is
a perennial plant with biennial shoots: first-year canes grow, second-year canes flower and fruit,
then die. Bilberry likewise persists as a clonal dwarf shrub with relatively short-lived above-ground
shoots. `life_cycle = perennial` and `lifespan_years` describe the persistent plant. The resource `description` says this for raspberry; the data does not simulate separate shoot
age cohorts.

Touch-me-not balsam is an annual: it completes its life cycle in one season and relies on seed for
the next generation. The resource records `life_cycle = annual` and `lifespan_years = 1.0`, but the
data layer supplies traits to the shared `ForestTrees` model, which owns finite seed
C/N/P, seasonal annual mortality and local recruitment. `initial_age_years` and
`mature_age_years` supply further traits to the model layer.

## Animal resources and individual appearance

`data/animals/hare.tres` (*Lepus timidus*), `fox.tres` (*Vulpes vulpes*) and
`bank_vole.tres` (*Myodes glareolus*) use
one model/primitive builder. `trophic_role`, `prey_species`, local perception,
movement, metabolism, life-history and primitive part roles are data. There is no
renderer branch for a species name. ADW links identify the animals and broad natural
history. Locomotion and demographic coefficients are set by the scenario.

The 24 hares, two foxes and 48 voles are finite initial conditions. Hare litters are
paid from maternal C/N/P before gestation, then transferred to stable append-only
newborn IDs. Age-specific reserve thresholds/mesh size grow over 120 model days;
the baseline litter is two after 30 days, with a 60-day cooldown. Predator reproduction
is disabled. Energetics, reproduction and movement use scenario-scale coefficients.

Voles consume the same finite plant stocks, flee predators and fund four pups
before a 21-day gestation; maturity/cooldown are 60/30 days. Their short round ears,
russet back and short tail are resource-only morphology. The ADW account supports
identity, forest habitat and broad diet. Burrows and separate seed/invertebrate
feeding channels remain open work. Reproductive reserve safety margins scale
with body reserve capacity.

Fox basal expenditure is 0.018 kg C/day (formerly 0.075); movement still costs C.
Two-day hunting bouts alternate with half-day rests; a catch also starts recovery,
and critical hunger interrupts recovery. Search goals are local persistent patrol
legs, never distant prey positions. Hunger interrupts tired herbivore excursions
before fatigue can restart another excursion. All timers, goals and reserves are
saved; animal behavior schema is v5 and rejects the previous configuration.

Six saved cosmetic values control body proportions, ear length/angle and coat/saddle
shade. Newborn appearance is parental mean plus bounded variation; none of these
values silently alters fitness. The view never draws RNG or advances biology.
See [the population verification](../verification/2026-10-31-population.md).


## Дополнительные общие признаки 2026-11-01

- `flower_start_day`, `flower_duration_days`, `insect_pollinated`,
  `fruit_bearing`, `fruit_start_day`, `fruit_duration_days`: общий конечный
  сезон цветения/урожая, без отдельной модели на каждый вид.
- `nurse_log_affinity` (0–1): вероятность предпочесть доступное место у
  валежника при рассеивании. Дальность/занятость/вода/свет и расход семени
  остаются общими ограничениями. Ноль сохраняет обычное рассеивание.
- `snow_retention` (0–1): сценарное удержание снега кроной, отображение и
  производный риск падения. Вода учитывается в общем снегозапасе погоды.
- `trampling_resistance` (0–1): удерживаемая доля сопротивления низкого
  живого покрова проходам. Сломанная масса переходит в почвенную подстилку;
  деревья и растения выше 1.2 м этим каналом не повреждаются.

Все новые параметры включены в контракт конфигурации целого сохранения.
Ни одна из этих веток не сравнивает строковое имя вида.


## Кабан · 2026-11-01

`data/animals/boar.tres`, *Sus scrofa*: 4 исходные особи, узнаваемая ресурсная
морфология и общие AnimationPlayer/Blender-клипы. Всеядность использует конечные
плоды, растительную биомассу, насекомых и падаль. `vegetation_fallback` разрешает
растительный корм при отсутствии спелых плодов; `rooting_pressure_day` задаёт
нарушение земли за биодень успешной наземной кормёжки.

Порои (`ForestHabitat.rooting`) повреждают низкий покров через существующий
`trample` с C/N/P-возвратом в `ForestSoil`; поле медленно затухает.
Оно безразмерное и описывает степень нарушения покрова. Корни не выделены в отдельный пищевой пул; стада/грязевые ванны и лактация
не реализованы. Беременность 115 биодней/3 детёныша — сценарная ресурсная
параметризация. Естественная история:
https://animaldiversity.org/accounts/Sus_scrofa/ . Проверки и границы:
[отчёт](../verification/2026-11-01-boars.md).

## Визуальные признаки крон и ветвей · 2026-11-02

Общие поля `ForestPlantDefinition`:

- `canopy_texture`, `canopy_leaf_span_m`, `canopy_color`: процедурная маска,
  физический масштаб листа и согласованный цвет. Маска — данные, цвет — sRGB.
- `canopy_layers`: 0 оставляет обычную морфологию; 4 даёт четыре близкие
  оболочки и две в среднем LoD. Их координаты закреплены на растении.
- `branch_radius_m`, `branch_droop`: связный сужающийся изогнутый каркас между
  стволами и существующими модулями кроны. Каркас задаёт геометрию растения.
- `bark_markings`: отметины на самой коре. Компоненты `branch` и `bark_detail`
  заменяются общим каркасом/материалом только при включённом соответствующем признаке.

20 древесных видов получают оболочки, остальные девять сохраняют прежние
геометрические компоненты. Цветы и плоды остаются отдельными тегами.
Эти поля и геометрические модули **не входят** в биологический `_configuration`
деревьев; схема сохранения мира не меняется. Отрисовка не меняет C/N/P,
размещение, возраст, фенологические параметры или запасы пищи.
Профили масок: `art/canopy/profiles.json`; генератор: `tools/bake_canopy_assets.py`.

## Начальные группы животных · 2026-11-02

Пары основателей выбирают разнесённые участки по всей области. Общий проход собирает сухие, достаточно пологие точки
возле существующего корма; если доступного корма нет, использует сухие точки
растительности. Для каждой новой пары максимизируется расстояние до уже
занятых участков, нормированное на `founder_pair_spacing_m` обеих групп.
Выбранные участки общие для всех видов: новый ресурс не получает отдельную
ветку кода. Два члена пары остаются примерно в 2 м друг от друга.

Размещение применяется при создании мира. Численность задаётся `initial_count`;
дальнейшие рождения, смерть и движение рассчитывает модель животных. В маленьких тестовых камерах с единственной подходящей точкой пары
используют доступное место. Количества, ID, исходный возраст и биологические параметры прежние.
