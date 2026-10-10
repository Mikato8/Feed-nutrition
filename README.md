# feed
## Notification
**This package is under development.**

## Overview

feed is a package for animal feed formulation. It is comprised of 3 parts; 1) import feedstuff information, 2) set nutrient requirement of animals, and 3) least-cost formulation.  

## Installation  

``` r
# The development version from GitHub:
# install.packages("devtools")
devtools::install_github("Mikato8/Feed-nutrition")
```

Dependencies: `shiny`, `DT` (interfaz) y `lpSolve` (formulación de mínimo costo).

``` r
install.packages(c("shiny", "DT", "lpSolve"))
```

## Usage
### Feed information
#### feed.list
feed.list function shows the list of feeds of [feedipedia.org](https://www.feedipedia.org/).

``` r
library(feed)

# All feeds
feed.list(category=all)

# Forage plants
feed.list(forage)

# Plant products/by-products
feed.list(plantProduct)

# Feeds of animal origin
feed.list(animalOrigin)

# Other feeds
feed.list(other)
```

#### feed.search
feed.search function shows the results you found at [feedipedia.org](https://www.feedipedia.org/).     

``` r
feed.search("maize")
```

#### feed.info
feed.info function show the nutritive values of the specific feedstuff(url) in the form of a list.

``` r
# The result of Maize germ meal and maize germ. url was found in the results of feed.search() function

feed.info(url="https://www.feedipedia.org/node/716")
```

#### feed.extract
feed.extract function extract the nutritive values from the the list.

``` r
# The result of "Maize germ meal, protein 20-30%, oil > 5%". url was found in the results of feed.search() function and n was found in feed.list() function (e.g. [[3]])

feed.extract(url="https://www.feedipedia.org/node/716",n=3)
```

### Conversion
#### as_is
as_is function convert dry-matter basis into as-is basis.

``` r
df <- data.frame(nutrient=c("CP","NDF","EE","Ash"),composition=c(10,30,5,2))
as_is(composition=df$composition,dm=85,digits=2)
```

#### d_m
d_m function convert as-is basis into dry-mater basis.

``` r
df <- data.frame(nutrient=c("CP","NDF","EE","Ash"),composition=c(10,30,5,2))
d_m(composition=df$composition,dm=85,digits=2)
```

### Dataset

#### feed.nrc.beef
feed.nrc.beef function loads the feed informations from [BCNRM 2016](http://nutritionmodels.com/beef.html) (Drs. Noel Andy Cole, Clinton R. Krehbiel, Ronald P. Lemenager, Galen E. Erickson, Joel Caton, Karen A. Beauchemin, Michael L. Galyean, Joan H. Eisemann, and Luis O. Tedeschi).

``` r
feed.nrc.beef

#check the unit
attributes(feed.nrc.beef)$unit
#or
str(feed.nrc.beef)
```

## Getting helps
Email: ruminoreticulum@gmail.com

---

## Base de datos editable y calculadora de nutrición

Además de los datos de referencia (`feed.nrc.beef`), que **nunca se modifican**,
el paquete mantiene una **base de datos propia del usuario** en un CSV local,
donde cada quien puede agregar sus ingredientes, ajustar precios y valores, y
usar una calculadora de nutrición y formulación de mínimo costo.

La ruta del CSV se puede personalizar con `options(feed.db = "...")` o con la
variable de entorno `FEED_DB`; por defecto es `~/.feed/ingredients.csv`.

> Unidades: la base guarda los nutrientes con las mismas unidades que la
> referencia (por ejemplo `CP` en `%DM`). La calculadora y la formulación
> convierten automáticamente a base "tal cual" (as-fed) usando la materia seca.

### Gestión de ingredientes

``` r
library(feed)

# Inicializar / ver la base
ingredient_init()
ingredient_load()

# Añadir un ingrediente propio (precio y valores ajustables)
ingredient_add("Maíz propio", DM = 88, CP = 8, TDN = 80, Cost = 250)

# Copiar un ingrediente de referencia para poder editarlo (la referencia queda intacta)
ingredient_from_reference("Maize grain")

# Editar valores / precio de un ingrediente existente
df <- ingredient_load()
ingredient_update(df$id[1], Cost = 280, CP = 9)

# Borrar
ingredient_remove(df$id[2])

# Catálogo combinado (referencia + propios)
ingredient_catalog()
```

### Compartir la base de datos

``` r
ingredient_export(file = "mis-ingredientes.csv")  # exportar
ingredient_import("mis-ingredientes.csv")         # importar / fusionar
```

### Calculadora de nutrición

``` r
cat <- ingredient_catalog()
sel <- cat[cat$Feed %in% c("Maize grain", "Soybean meal"), ]
feed_calc(sel, amounts = c(60, 40))
# $weight, $cost, $cost_per_kg, $nutrients
```

### Formulación de mínimo costo (LP)

``` r
cat <- ingredient_catalog()
sel <- cat[cat$Feed %in% c("Maize grain", "Soybean meal", "Alfalfa hay"), ]

# Requerimientos: mínimo/máximo por nutriente (NA = sin límite)
cons <- data.frame(
  nutrient = c("CP", "TDN"),
  min      = c(12, 70),
  max      = c(NA, NA)
)

feed_formulate(sel, cons, total = 100)
```

### Sugerencias de productos

``` r
feed_suggest("Maize grain", top_n = 5)
# ingredientes similares con su precio (y si son más baratos)
```

### Aplicación web (Shiny)

``` r
feed::run_feed_app()
```

Abre una app con cuatro pestañas:

1. **Ingredientes** — ver la referencia (solo lectura), copiar a tu base,
   editar celdas (precio/valores), añadir, borrar, exportar e importar CSV.
2. **Calculadora** — elegir ingredientes y cantidades; total de nutrientes y costo.
3. **Formulación** — seleccionar ingredientes y requerimientos; mezcla de mínimo costo.
4. **Sugerencias** — alternativas similares y más baratas para un ingrediente.
