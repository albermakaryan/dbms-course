# Datasets

**Planned course spine:** the [Olist Brazilian e-commerce dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
(orders, customers, products, reviews — realistic scale and mess). Final
choice pending (Olist vs. Pagila vs. instructor-built); a **separate fresh
dataset is reserved for the midterm** and is never published here.

## Rules for this directory

- **Load scripts live here — never data dumps.** No CSVs, no `.sql` dumps of
  data, nothing large or licensed. Scripts should download/transform/load
  from the original source.
- One subdirectory per dataset (e.g. `olist/`), each with its own README:
  source URL, license, load instructions, target schema.
- Anything containing real personal data never enters this repo, full stop.

## Planned layout (placeholder)

```
datasets/
├── README.md          # this file
└── olist/             # [PLANNED]
    ├── README.md      # source, license, schema notes
    └── load.sh        # download from source + psql load
```
