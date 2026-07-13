# Content pipeline

`bank.json` is the single source of truth for the app's content. It is generated
from the transcribed question bank and rendered to LaTeX.

    tools/export_bank.py   ->  data/bank.json        (questions, answers, solutions, concepts)
    tools/gen_seed.py      ->  ../supabase/seed.sql
    tools/validate_latex.mjs                          (parses every $...$ span with KaTeX)
    ../supabase/test_schema.sh                        (loads schema+seed into Docker Postgres, tests the engine)

## Why the questions were transcribed by hand

`pdftotext` **destroys** the maths in these papers — `(-3p^-3)^2` comes out as garbage
and fractions collapse. There is no reliable automatic text path from the source PDFs.
The 107 questions were read visually and transcribed. See ADR-013.

## Always re-validate after touching the converter

    python3 tools/export_bank.py && node tools/validate_latex.mjs

Must report `parse failures : 0`. An early version of the converter emitted 172 broken
spans because regexes were re-matching inside already-converted LaTeX.
