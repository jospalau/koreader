--[[
  MoodReader genre presets

  Tamaños de fuente entre 8.5pt y 11pt seleccionados por confort de lectura en pantallas de 300ppi.
  line_spacing_percent representa el interlineado relativo, partiendo de una base de 1.2em = 100%:

    - 92  → 1.1em  (compacto)
    - 96  → 1.15em
    - 100 → 1.2em   (por defecto KOReader/Calibre)
    - 104 → 1.25em
    - 109 → 1.3em
    - 113 → 1.35em
    - 117 → 1.4em   (muy aireado)

  Estos perfiles buscan un equilibrio entre legibilidad, atmósfera y compacidad según género.
]]
return {  ["Fantasy"] = {
    description = "Elegant, classic serif fonts without being too decorative. A touch of character and warmth.",
    fonts = "Andada Pro, Candide, Charis SIL, Gentium Book Plus, Georgia Pro, Libre Caslon Text, Literata, Palatino, Utopia, XCharter",
    presets = {
      { font = "Literata", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Palatino", size = 10, weight = 0.6, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Charis SIL", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Gentium Book Plus", size = 10.5, weight = 0.5, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Libre Caslon Text", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "XCharter", size = 10, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Utopia", size = 10, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Georgia Pro", size = 9.5, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Andada Pro", size = 10, weight = 0.7, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Candide", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 }
    }
  },  ["High Fantasy"] = {
    description = "More solemn and evocative. Almost medieval in atmosphere, with a traditional tone.",
    fonts = "Adobe Jenson Pro, Alegreya, Athelas, Crimson Text, EB Garamond, Goudy Old Style, Iowan Old Style, Libre Baskerville, Minion Pro, Source Serif Pro",
    presets = {
      { font = "Libre Baskerville", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "EB Garamond", size = 11, weight = 0.7, line_spacing_percent = 116, line_spacing_em = 1.4 },
      { font = "Adobe Jenson Pro", size = 11, weight = 0.7, line_spacing_percent = 116, line_spacing_em = 1.4 },
      { font = "Alegreya", size = 10.5, weight = 0.6, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Iowan Old Style", size = 10, weight = 0.6, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Goudy Old Style", size = 11, weight = 0.7, line_spacing_percent = 116, line_spacing_em = 1.4 },
      { font = "Athelas", size = 10.5, weight = 0.6, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Minion Pro", size = 10.5, weight = 0.5, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Source Serif Pro", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Crimson Text", size = 10.5, weight = 0.6, line_spacing_percent = 108, line_spacing_em = 1.3 }
    }
  },  ["Dark Fantasy"] = {
    description = "Fonts with higher contrast and visual density to evoke a darker, heavier atmosphere.",
    fonts = "Aleo, Arbutus Slab, Arvo, Averia Serif, Charter, Domine, Lexia DaMa, Merriweather, UglyQua, Vollkorn",
    presets = {
      { font = "Merriweather", size = 9.5, weight = 0.6, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Arvo", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Arbutus Slab", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Aleo", size = 9.5, weight = 0.6, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Domine", size = 9, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Vollkorn", size = 10.5, weight = 0.4, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Charter", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Averia Serif", size = 10, weight = 0.6, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Lexia DaMa", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "UglyQua", size = 10, weight = 0.6, line_spacing_percent = 100, line_spacing_em = 1.2 }
    }
  },  ["Science Fiction"] = {
    description = "Modern sans-serifs with a clean, sometimes slightly futuristic design.",
    fonts = "Amazon Ember, Atkinson Hyperlegible, Lexend Deca, Luciole, Noticia Text, PMN Caecilia, Readex Pro, Roboto, Tiempos Headline, Verdana Pro",
    presets = {
      { font = "Roboto", size = 9.5, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Amazon Ember", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Lexend Deca", size = 9, weight = 0.5, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Readex Pro", size = 9.5, weight = 0.5, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Luciole", size = 9.5, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Noticia Text", size = 10, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Verdana Pro", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Tiempos Headline", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Atkinson Hyperlegible", size = 10, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "PMN Caecilia", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 }
    }
  }, ["Science Fantasy"] = {
  description = "A fusion of elegance and modernity. Balanced serif and hybrid fonts evoking both magic and science.",
  fonts = "Arsenal, Bookerly, Caladea, Canela Text, Charis SIL, PT Serif, Readex Pro, Source Sans 3, Souvenir, Stria",
  presets = {
      { font = "Canela Text", size = 10, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Bookerly", size = 10, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Souvenir", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Caladea", size = 10, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "PT Serif", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Arsenal", size = 9.5, weight = 0.6, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Source Sans 3", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Stria", size = 8.5, weight = 0.5, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Readex Pro", size = 9.5, weight = 0.5, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Charis SIL", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 }
  }
}, ["Thriller"] = {
    description = "Tight, direct, tense. Clear sans-serif fonts that maintain urgency without coldness.",
    fonts = "Adler, Amazon Ember, Arvo, Atkinson Hyperlegible, Lexend Deca, Luciole, Merriweather, Roboto, Source Sans 3, Tinos",
    presets = {
      { font = "Adler", size = 9, weight = 0.6, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Lexend Deca", size = 9, weight = 0.5, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Roboto", size = 9.5, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Tinos", size = 10.5, weight = 0.4, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Source Sans 3", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Atkinson Hyperlegible", size = 10, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Amazon Ember", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Luciole", size = 9.5, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Merriweather", size = 9.5, weight = 0.6, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Arvo", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 }
    }
  },  ["Horror"] = {
    description = "Traditional serif fonts with a decadent, sometimes poetic feel. Elegant but unsettling.",
    fonts = "Aleo, Arvo, Crimson Text, IM FELL DW Pica, Libre Caslon Text, Luciole, Merriweather, Old Standard TT, Spectral, Vollkorn",
    presets = {
      { font = "Spectral", size = 10.5, weight = 0.6, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Old Standard TT", size = 11, weight = 0.7, line_spacing_percent = 116, line_spacing_em = 1.4 },
      { font = "Vollkorn", size = 10.5, weight = 0.4, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Aleo", size = 9.5, weight = 0.6, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Crimson Text", size = 11, weight = 0.6, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "IM FELL DW Pica", size = 11, weight = 0.7, line_spacing_percent = 116, line_spacing_em = 1.4 },
      { font = "Merriweather", size = 9.5, weight = 0.6, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Luciole", size = 9.5, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Arvo", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Libre Caslon Text", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 }
    }
  },  ["Historical Fantasy"] = {
    description = "Readable but classic-looking serif fonts. Clear and spacious for immersive prose.",
    fonts = "Adobe Jenson Pro, Athelas, EB Garamond, Gentium Book Plus, Georgia Pro, Iowan Old Style, Libre Baskerville, Libre Caslon Text, Old Standard TT, Palatino",
    presets = {
      { font = "Libre Caslon Text", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Libre Baskerville", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "EB Garamond", size = 11, weight = 0.7, line_spacing_percent = 116, line_spacing_em = 1.4 },
      { font = "Adobe Jenson Pro", size = 11, weight = 0.7, line_spacing_percent = 116, line_spacing_em = 1.4 },
      { font = "Old Standard TT", size = 11, weight = 0.7, line_spacing_percent = 116, line_spacing_em = 1.4 },
      { font = "Palatino", size = 10, weight = 0.6, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Athelas", size = 10.5, weight = 0.6, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Iowan Old Style", size = 10, weight = 0.6, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Gentium Book Plus", size = 10.5, weight = 0.5, line_spacing_percent = 108, line_spacing_em = 1.3 },
      { font = "Georgia Pro", size = 10, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 }
    }
  },  ["Contemporary"] = {
    description = "Neutral, modern, and straightforward fonts. Comfortable for day-to-day reading.",
    fonts = "Amazon Ember, Bookerly, Georgia Pro, Lexend Deca, Literata, Palatino, PMN Caecilia, PT Serif, Roboto, XCharter",
    presets = {
      { font = "Georgia Pro", size = 9.5, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Literata", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Bookerly", size = 10, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "XCharter", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Palatino", size = 10, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "PMN Caecilia", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Amazon Ember", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Lexend Deca", size = 9, weight = 0.5, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Roboto", size = 9.5, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "PT Serif", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 }
    }
  },  ["Non-Fiction"] = {
    description = "Professional, neutral fonts prioritizing clarity, structure and focus.",
    fonts = "APHont, Atkinson Hyperlegible, Charter, Lexend Deca, Luciole, OpenDyslexic, PT Serif, Roboto, Source Sans 3, Tinos",
    presets = {
      { font = "APHont", size = 9.5, weight = 0.6, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Atkinson Hyperlegible", size = 10, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Lexend Deca", size = 9, weight = 0.5, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Luciole", size = 9.5, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Roboto", size = 9.5, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Tinos", size = 10, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Charter", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Source Sans 3", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "PT Serif", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "OpenDyslexic", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 }
    }
  },  ["Dystopia"] = {
    description = "Compact fonts evoking a sense of control, oppression or minimalism.",
    fonts = "Adler, Amazon Ember, Arvo, Atkinson Hyperlegible, Lexend Deca, Luciole, PMN Caecilia, Roboto, Source Sans 3, Times New Roman",
    presets = {
      { font = "Amazon Ember", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "PMN Caecilia", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Roboto", size = 9.5, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Luciole", size = 9.5, weight = 0.4, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Atkinson Hyperlegible", size = 10, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Lexend Deca", size = 9, weight = 0.5, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Source Sans 3", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Arvo", size = 9.5, weight = 0.4, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Adler", size = 9, weight = 0.6, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "Times New Roman", size = 10.5, weight = 0.5, line_spacing_percent = 108, line_spacing_em = 1.3 }
    }
  },  ["Young Adult"] = {
    description = "Accessible, fresh and easy-to-read sans fonts. Open curves and modern rhythm.",
    fonts = "Amazon Ember, Andika eBook, APHont, Atkinson Hyperlegible, Bookerly, Charis SIL, Lexend Deca, Literata, OpenDyslexic, Verdana Pro",
    presets = {
      { font = "Lexend Deca", size = 9, weight = 0.5, line_spacing_percent = 92, line_spacing_em = 1.1 },
      { font = "OpenDyslexic", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Atkinson Hyperlegible", size = 10, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "APHont", size = 9.5, weight = 0.6, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Bookerly", size = 10, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Amazon Ember", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Andika eBook", size = 10, weight = 0.4, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Charis SIL", size = 10, weight = 0.5, line_spacing_percent = 100, line_spacing_em = 1.2 },
      { font = "Literata", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 },
      { font = "Verdana Pro", size = 9.5, weight = 0.5, line_spacing_percent = 96, line_spacing_em = 1.15 }
    }
  },
}
