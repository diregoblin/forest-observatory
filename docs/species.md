# Species resources

All nine species are plain `ForestPlantDefinition` resources in `data/plants/` and are listed in
`data/forest.tres`. They share the existing `ForestPlantMeshBuilder` and placement model; there are
no species-specific branches in code. Geometry differs only through reusable modules
(stems, branches, leaf clusters, flowers, fruit) and their transforms.

| Resource | Russian name | Latin name | Growth form | Life cycle | Source |
| --- | --- | --- | --- | --- | --- |
| `spruce.tres` | Ель обыкновенная | *Picea abies* | tree | perennial | [POWO search](https://powo.science.kew.org/results?q=Picea%20abies) |
| `birch.tres` | Берёза повислая | *Betula pendula* | tree | perennial | [POWO search](https://powo.science.kew.org/results?q=Betula%20pendula) |
| `aspen.tres` | Осина | *Populus tremula* | tree | perennial | [POWO search](https://powo.science.kew.org/results?q=Populus%20tremula) |
| `grey_willow.tres` | Ива пепельная | *Salix cinerea* | shrub | perennial | [POWO search](https://powo.science.kew.org/results?q=Salix%20cinerea) |
| `raspberry.tres` | Малина обыкновенная | *Rubus idaeus* | shrub | perennial | [POWO search](https://powo.science.kew.org/results?q=Rubus%20idaeus) |
| `bilberry.tres` | Черника обыкновенная | *Vaccinium myrtillus* | dwarf shrub | perennial | [POWO search](https://powo.science.kew.org/results?q=Vaccinium%20myrtillus) |
| `wood_sorrel.tres` | Кислица обыкновенная | *Oxalis acetosella* | herb | perennial | [POWO search](https://powo.science.kew.org/results?q=Oxalis%20acetosella) |
| `tufted_hairgrass.tres` | Щучка дернистая | *Deschampsia cespitosa* | grass | perennial | [POWO search](https://powo.science.kew.org/results?q=Deschampsia%20cespitosa) |
| `balsam.tres` | Недотрога обыкновенная | *Impatiens noli-tangere* | herb | annual | [POWO search](https://powo.science.kew.org/results?q=Impatiens%20noli-tangere) |

## Scenario parameters, not measurements

The numeric fields (`biomass_kg_c`, `cn_ratio`, `cp_ratio`, `height_growth_m_year`,
`transpiration_m_s`, `seed_cost_kg_c`, `reproduction_per_year`, `dispersal_m`,
`germination_fraction`, `recruitment_light`, `dead_decay_per_year`, and the flood/stress values) are **qualitative
scenario assumptions**. They make the life forms behave differently in the prototype; they are not
measured allometry, a carbon inventory, or a validated demographic model. `biomass_kg_c` is carbon
at `size = 1`, not the mass of a real individual. The source links are taxonomic references for the
names and life forms only; they do not justify these coefficients.

`edible_fraction` is a conservative positive browse share for hare on a few understory sources
(grey willow, raspberry, bilberry, wood sorrel, tufted hairgrass). It is not a toxicity, food-safety,
or palatability claim for any species.

Initial placement uses the existing `weight` field. Tree weights are 0.52 (spruce), 0.28 (birch) and
0.20 (aspen), totaling about 1.0. Understory weights total 0.75, so trees remain the majority of
initial individuals while the understory is present as distinct small life forms.

## Perennial clones and shoot age

A perennial genet can persist for many years while its shoots or ramets die and regrow. Raspberry is
a perennial plant with biennial shoots: first-year canes grow, second-year canes flower and fruit,
then die. Bilberry likewise persists as a clonal dwarf shrub with relatively short-lived above-ground
shoots. `life_cycle = perennial` and `lifespan_years` describe the persistent plant, not a single
shoot. The resource `description` says this for raspberry; the data does not simulate separate shoot
age cohorts.

Touch-me-not balsam is an annual: it completes its life cycle in one season and relies on seed for
the next generation. The resource records `life_cycle = annual` and `lifespan_years = 1.0`, but the
data layer supplies traits to the shared `ForestTrees` model, which owns finite seed
C/N/P, seasonal annual mortality and local recruitment. `initial_age_years` and
`mature_age_years` are likewise metadata for the model layer, not calibration data.
