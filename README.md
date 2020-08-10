# Data-Dictionary-Searcher
A search interface against the Oracle Data Dictionary that is useful for template based code generators.


Search Packages (and functions)
---
- MK_DD - Collection of Pipeline functions by MikeKutz (MK)
  - get_columns() - simple column name search
  - *others*      - TBD
 - `dd` - older version (deprecated for normal uses)

Search String Options
---
Space separated list of tokens

default is `'* -hidden -system'`

Token inclusion/exclusion
---
- prefix of `+` = Include this column type
- prefix of `-` = Exclude this column type
- no prefix = Only show this columns time. (only one)
- `*` = wild card (show ALL column)

List of Tokens
---
- `PK` - Primary Key column
- `ID` - Identity Column (or "only PK column that is type NUMBER")
- `NULLABLE` - nullable/not null columns
- `HIDDEN` - Hidden columne
- `VIRTUAL` - virtual columns
- `SYSTEM`  - System generated column (12c+)
- `DEFAULT` - column has a DEFAULT value (bugged)
- `PARTKEY` - Partition key (not yet available)
- `FK` - Column is a Foreign Key column (not yet available)

Examples
===
- To get only PK columns, use `'PK'`
- To get non PK columns/non virtual columns, use `'-PK -VIRTUAL'`
- To get only Virtual Column, use `'VC'`
