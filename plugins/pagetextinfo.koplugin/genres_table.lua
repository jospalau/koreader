--[[
  MoodReader genre presets (v3)

  Fuentes re-seleccionadas por género con dos criterios a la vez:
    1. Encaje con la atmósfera del género.
    2. Legibilidad según readability_table.lua (campo `readability`).

  El PRIMER preset de cada género es el recomendado por defecto; el resto va
  ordenado de mayor a menor encaje con el género.

  Todos los nombres de fuente son claves que existen en readability_table.lua,
  para que la consulta de legibilidad funcione siempre.

  Interlineado relativo a una base de 1.2em = 100%:
    92 → 1.1em | 96 → 1.15em | 100 → 1.2em | 104 → 1.25em
    108 → 1.3em | 113 → 1.35em | 117 → 1.4em

  Reglas de ajuste por legibilidad:
    HIGH   → size 9.5 (9 si x-height >= 54%), weight 0.4, interlineado del género - 0.05em
    MEDIUM → size 10 (9.5 en sans con x-height >= 50%, 10.5 si x-height es borderline),
             weight 0.5 (0.6 si hairline < 4%, 0.4 en sans de trazo robusto)
    LOW    → size 10.5 (11 si x-height <= 41%), weight 0.7 (0.8 si hairline < 3%),
             interlineado del género + 0.05em
    Condensadas: +0.5pt de size para compensar el ancho estrecho.
    Dark Fantasy y Horror: +0.1 de weight en fuentes HIGH para dar densidad.

  Interlineado base (em): Fantasy 1.2 | High Fantasy 1.3 | Dark Fantasy 1.2 |
    Science Fiction 1.15 | Science Fantasy 1.2 | Thriller 1.15 | Horror 1.3 |
    Historical Fantasy 1.25 | Contemporary 1.2 | Non-Fiction 1.2 |
    Dystopia 1.15 | Young Adult 1.2     (mínimo 1.1, máximo 1.4)

  Máximo 2 fuentes LOW por género, y solo en géneros donde la atmósfera lo pide.
]]
return {
  ["Fantasy"] = {
    description = "Elegant, warm serif fonts with a touch of character. Classic without being decorative.",
    fonts = "Literata Book, Palatino, Lora, Andada Pro, Faustina, Libre Baskerville, Charis SIL, Gentium Book Plus, Canela Text, Libre Caslon Text",
    presets = {
      { font = "Literata Book", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Palatino", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Lora", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Andada Pro", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Faustina", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Libre Baskerville", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Charis SIL", readability = "MEDIUM", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Gentium Book Plus", readability = "MEDIUM", size = 10.5, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Canela Text", readability = "MEDIUM", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Libre Caslon Text", readability = "MEDIUM", size = 10, weight = 0.6, line_spacing_percent = 100, line_spacing_em = 1.2 }
    }
  },
  ["High Fantasy"] = {
    description = "Solemn and evocative, almost medieval in atmosphere. Old-style serifs with a traditional tone.",
    fonts = "Libre Baskerville, Besley, Alegreya, Iowan Old Style, Rosarivo, ITC Mendoza Roman Std, Caudex, Baskerville 10 Pro, EB Garamond, Adobe Jenson Pro",
    presets = {
      { font = "Libre Baskerville", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 104, line_spacing_em = 1.25 },
      { font = "Besley", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 104, line_spacing_em = 1.25 },
      { font = "Alegreya", readability = "MEDIUM", size = 10.5, weight = 0.5, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Iowan Old Style", readability = "MEDIUM", size = 10, weight = 0.6, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Rosarivo", readability = "MEDIUM", size = 10, weight = 0.6, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "ITC Mendoza Roman Std", readability = "MEDIUM", size = 10, weight = 0.5, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Caudex", readability = "MEDIUM", size = 10, weight = 0.6, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Baskerville 10 Pro", readability = "MEDIUM", size = 10, weight = 0.6, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "EB Garamond", readability = "LOW", size = 11, weight = 0.7, line_spacing_percent = 113, line_spacing_em = 1.35 },
      { font = "Adobe Jenson Pro", readability = "LOW", size = 11, weight = 0.7, line_spacing_percent = 113, line_spacing_em = 1.35 }
    }
  },
  ["Dark Fantasy"] = {
    description = "Heavy slabs and high-contrast serifs with visual density, for a darker, weightier atmosphere.",
    fonts = "Merriweather, Domine, Aleo, Bitter Pro, Arbutus Slab, UglyQua, Amarante, Fraunces 9pt, Vollkorn, Libre Caslon Text",
    presets = {
      { font = "Merriweather", readability = "HIGH", size = 9, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Domine", readability = "HIGH", size = 9, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Aleo", readability = "HIGH", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Bitter Pro", readability = "HIGH", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Arbutus Slab", readability = "HIGH", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "UglyQua", readability = "HIGH", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Amarante", readability = "HIGH", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Fraunces 9pt", readability = "MEDIUM", size = 10, weight = 0.6, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Vollkorn", readability = "MEDIUM", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Libre Caslon Text", readability = "MEDIUM", size = 10, weight = 0.6, line_spacing_percent = 100, line_spacing_em = 1.2 }
    }
  },
  ["Science Fiction"] = {
    description = "Clean, modern fonts, mostly geometric or technical sans-serifs with two engineered serifs. Compact and slightly futuristic.",
    fonts = "Sora, B612, Luciole, IBM Plex Serif, Tiempos Text, Atkinson Hyperlegible Next, Lexend Deca, Readex Pro, IBM Plex Sans, Metropolis",
    presets = {
      { font = "Sora", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "B612", readability = "HIGH", size = 9, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Luciole", readability = "HIGH", size = 9, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "IBM Plex Serif", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Tiempos Text", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Atkinson Hyperlegible Next", readability = "MEDIUM", size = 10, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Lexend Deca", readability = "MEDIUM", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Readex Pro", readability = "MEDIUM", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "IBM Plex Sans", readability = "MEDIUM", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Metropolis", readability = "MEDIUM", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 }
    }
  },
  ["Science Fantasy"] = {
    description = "A fusion of elegance and modernity. Contemporary, screen-friendly serifs evoking both magic and science.",
    fonts = "Bookerly, Libron, Noticia Text, PT Serif, Rakuten Serif, Mikadan, Scriptoria, Canela Text, Souvenir, Source Serif 4",
    presets = {
      { font = "Bookerly", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Libron", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Noticia Text", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "PT Serif", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Rakuten Serif", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Mikadan", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Scriptoria", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Canela Text", readability = "MEDIUM", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Souvenir", readability = "MEDIUM", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Source Serif 4", readability = "MEDIUM", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 }
    }
  },
  ["Thriller"] = {
    description = "Tight, direct, tense. Clear sans-serifs plus a few punchy slab/serif faces that keep urgency without coldness.",
    fonts = "Adler, Lato, Luciole, Bitter Pro, Droid Serif, Roboto, Source Sans 3, Amazon Ember, Atkinson Hyperlegible Next, Seravek",
    presets = {
      { font = "Adler", readability = "HIGH", size = 9, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Lato", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Luciole", readability = "HIGH", size = 9, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Bitter Pro", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Droid Serif", readability = "HIGH", size = 9, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Roboto", readability = "MEDIUM", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Source Sans 3", readability = "MEDIUM", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Amazon Ember", readability = "MEDIUM", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Atkinson Hyperlegible Next", readability = "MEDIUM", size = 10, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Seravek", readability = "MEDIUM", size = 10, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 }
    }
  },
  ["Horror"] = {
    description = "Decadent, poetic serifs with sharp contrast and an old-book feel. Elegant but unsettling.",
    fonts = "Lora, Spectral, Brygada 1918, Castoro, Antykwa Torunska, Candide, Plantin MT Pro, IM FELL DW Pica, Fenix, Old Standard TT",
    presets = {
      { font = "Lora", readability = "HIGH", size = 9.5, weight = 0.5, line_spacing_percent = 104, line_spacing_em = 1.25 },
      { font = "Spectral", readability = "MEDIUM", size = 10.5, weight = 0.5, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Brygada 1918", readability = "MEDIUM", size = 10, weight = 0.6, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Castoro", readability = "MEDIUM", size = 10, weight = 0.6, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Antykwa Torunska", readability = "MEDIUM", size = 10, weight = 0.6, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Candide", readability = "MEDIUM", size = 10, weight = 0.6, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Plantin MT Pro", readability = "MEDIUM", size = 10, weight = 0.6, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Fenix", readability = "MEDIUM", size = 10.5, weight = 0.5, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "IM FELL DW Pica", readability = "MEDIUM", size = 10.5, weight = 0.6, line_spacing_percent = 113, line_spacing_em = 1.35 },
      { font = "Old Standard TT", readability = "LOW", size = 11, weight = 0.8, line_spacing_percent = 113, line_spacing_em = 1.35 }
    }
  },
  ["Historical Fantasy"] = {
    description = "Readable but classic-looking serif fonts. Clear and spacious for immersive prose.",
    fonts = "Palatino, Georgia, Libre Baskerville, Plantin MT Pro, Georgia Pro, Constantia, Utopia, Liberation Serif, Gelasio eBook, Sabon Next LT",
    presets = {
      { font = "Palatino", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Georgia", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Libre Baskerville", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Plantin MT Pro", readability = "MEDIUM", size = 10, weight = 0.6, line_spacing_percent = 104, line_spacing_em = 1.25 },
      { font = "Georgia Pro", readability = "MEDIUM", size = 10, weight = 0.5, line_spacing_percent = 104, line_spacing_em = 1.25 },
      { font = "Constantia", readability = "MEDIUM", size = 10, weight = 0.5, line_spacing_percent = 104, line_spacing_em = 1.25 },
      { font = "Utopia", readability = "MEDIUM", size = 10, weight = 0.6, line_spacing_percent = 104, line_spacing_em = 1.25 },
      { font = "Liberation Serif", readability = "MEDIUM", size = 10, weight = 0.6, line_spacing_percent = 104, line_spacing_em = 1.25 },
      { font = "Gelasio eBook", readability = "MEDIUM", size = 10, weight = 0.5, line_spacing_percent = 104, line_spacing_em = 1.25 },
      { font = "Sabon Next LT", readability = "LOW", size = 10.5, weight = 0.7, line_spacing_percent = 108, line_spacing_em = 1.3 }
    }
  },
  ["Contemporary"] = {
    description = "Neutral, modern, and straightforward fonts. Comfortable for day-to-day reading.",
    fonts = "Bookerly, Literata Book, PT Serif, Lato, Newsreader eBook, Charter eBook, XCharter, Amazon Ember, Figtree, Source Sans 3",
    presets = {
      { font = "Bookerly", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Literata Book", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "PT Serif", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Lato", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Newsreader eBook", readability = "MEDIUM", size = 10.5, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Charter eBook", readability = "MEDIUM", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "XCharter", readability = "MEDIUM", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Amazon Ember", readability = "MEDIUM", size = 9.5, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Figtree", readability = "MEDIUM", size = 9.5, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Source Sans 3", readability = "MEDIUM", size = 9.5, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 }
    }
  },
  ["Non-Fiction"] = {
    description = "Professional, neutral fonts prioritizing clarity, structure and focus, with accessibility-oriented options.",
    fonts = "IBM Plex Serif, Tiempos Text, PT Serif, Charter eBook, Source Serif 4, Atkinson Hyperlegible Next, Source Sans 3, Lexend Deca, APHont, OpenDyslexic",
    presets = {
      { font = "IBM Plex Serif", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Tiempos Text", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "PT Serif", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "APHont", readability = "HIGH", size = 9, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "OpenDyslexic", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Charter eBook", readability = "MEDIUM", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Source Serif 4", readability = "MEDIUM", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Atkinson Hyperlegible Next", readability = "MEDIUM", size = 10, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Source Sans 3", readability = "MEDIUM", size = 9.5, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Lexend Deca", readability = "MEDIUM", size = 9.5, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 }
    }
  },
  ["Dystopia"] = {
    description = "Compact, utilitarian fonts evoking control, oppression or minimalism. Condensed sans and one monospace.",
    fonts = "Adler, Luciole, Roboto, Roboto Condensed, Barlow Condensed, Saira Condensed, IBM Plex Sans, Source Sans 3, Tinos, Consolas",
    presets = {
      { font = "Adler", readability = "HIGH", size = 9, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Luciole", readability = "HIGH", size = 9, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Roboto", readability = "MEDIUM", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Roboto Condensed", readability = "MEDIUM", size = 10, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Barlow Condensed", readability = "MEDIUM", size = 10, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Saira Condensed", readability = "MEDIUM", size = 10, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "IBM Plex Sans", readability = "MEDIUM", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Source Sans 3", readability = "MEDIUM", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Tinos", readability = "MEDIUM", size = 10, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Consolas", readability = "MEDIUM", size = 9.5, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 }
    }
  },
  ["Young Adult"] = {
    description = "Accessible, fresh and easy-to-read fonts: open, friendly sans-serifs plus one clear screen serif. Modern rhythm.",
    fonts = "APHont, Bookerly, Poppins, Lexend Deca, Figtree, Inclusive Sans, Atkinson Hyperlegible Next, Andika eBook, Nunito, Charis SIL",
    presets = {
      { font = "APHont", readability = "HIGH", size = 9, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Bookerly", readability = "HIGH", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Poppins", readability = "HIGH", size = 9, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Lexend Deca", readability = "MEDIUM", size = 9.5, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Figtree", readability = "MEDIUM", size = 9.5, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Inclusive Sans", readability = "MEDIUM", size = 9.5, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Atkinson Hyperlegible Next", readability = "MEDIUM", size = 10, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Andika eBook", readability = "MEDIUM", size = 10, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Nunito", readability = "MEDIUM", size = 10, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Charis SIL", readability = "MEDIUM", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 }
    }
  },
}
