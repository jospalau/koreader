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
    fonts = "Andada Pro, Garamond Libre, Bitter Pro, Chartere Book, Vollkorn, Literata 72pt",
    presets = {
      { font = "Andada Pro", size = 10.0, weight = 0.5, line_spacing_percent = 100, line_spacing_em = "1.2em" },
      { font = "Garamond Libre", size = 10.4, weight = 0.375, line_spacing_percent = 109, line_spacing_em = "1.3em" },
      { font = "Bitter Pro", size = 9.8, weight = 0.5, line_spacing_percent = 104, line_spacing_em = "1.25em" },
      { font = "Chartere Book", size = 9.5, weight = 0.625, line_spacing_percent = 96, line_spacing_em = "1.15em" },
      { font = "Vollkorn", size = 9.6, weight = 0.625, line_spacing_percent = 109, line_spacing_em = "1.3em" },
      { font = "Literata 72pt", size = 9.7, weight = 0.5, line_spacing_percent = 104, line_spacing_em = "1.25em" },
    }
  },  ["High Fantasy"] = {
    description = "More solemn and evocative. Almost medieval in atmosphere, with a traditional tone.",
    fonts = "Literata 72pt, IM FELL DW Pica, Rosarivo, Crimson Pro, Spectral, Garamond Libre",
    presets = {
      { font = "Literata 72pt", size = 10.0, weight = 0.5, line_spacing_percent = 105, line_spacing_em = "1.25em" },
      { font = "IM FELL DW Pica", size = 10.8, weight = 0.375, line_spacing_percent = 110, line_spacing_em = "1.3em" },
      { font = "Rosarivo", size = 10.4, weight = 0.375, line_spacing_percent = 108, line_spacing_em = "1.3em" },
      { font = "Crimson Pro", size = 10.2, weight = 0.5, line_spacing_percent = 104, line_spacing_em = "1.25em" },
      { font = "Spectral", size = 10.0, weight = 0.625, line_spacing_percent = 100, line_spacing_em = "1.2em" },
      { font = "Garamond Libre", size = 10.5, weight = 0.375, line_spacing_percent = 111, line_spacing_em = "1.3em" },
    }
  },  ["Dark Fantasy"] = {
    description = "Fonts with higher contrast and visual density to evoke a darker, heavier atmosphere.",
    fonts = "EB Garamond, IM FELL DW Pica, Spectral, Literata 72pt, Rosarivo, Crimson Pro",
    presets = {
      { font = "EB Garamond", size = 10.2, weight = 0.375, line_spacing_percent = 106, line_spacing_em = "1.25em" },
      { font = "IM FELL DW Pica", size = 11.0, weight = 0.3, line_spacing_percent = 112, line_spacing_em = "1.35em" },
      { font = "Spectral", size = 10.0, weight = 0.625, line_spacing_percent = 105, line_spacing_em = "1.25em" },
      { font = "Literata 72pt", size = 10.2, weight = 0.5, line_spacing_percent = 106, line_spacing_em = "1.25em" },
      { font = "Rosarivo", size = 10.4, weight = 0.5, line_spacing_percent = 107, line_spacing_em = "1.3em" },
      { font = "Crimson Pro", size = 10.1, weight = 0.625, line_spacing_percent = 104, line_spacing_em = "1.25em" },
    }
  },  ["Science Fiction"] = {
    description = "Modern sans-serifs with a clean, sometimes slightly futuristic design.",
    fonts = "Inter, FiraGO, Source Sans Pro, Atkinson Hyperlegible, Lexend, IBM Plex Sans",
    presets = {
      { font = "Inter", size = 9.8, weight = 0.5, line_spacing_percent = 102, line_spacing_em = "1.2em" },
      { font = "FiraGO", size = 10.0, weight = 0.5, line_spacing_percent = 100, line_spacing_em = "1.2em" },
      { font = "Source Sans Pro", size = 10.2, weight = 0.375, line_spacing_percent = 98, line_spacing_em = "1.15em" },
      { font = "Atkinson Hyperlegible", size = 10.5, weight = 0.5, line_spacing_percent = 106, line_spacing_em = "1.25em" },
      { font = "Lexend", size = 10.0, weight = 0.5, line_spacing_percent = 100, line_spacing_em = "1.2em" },
      { font = "IBM Plex Sans", size = 9.9, weight = 0.625, line_spacing_percent = 101, line_spacing_em = "1.2em" },
    }
  }, ["Science Fantasy"] = {
  description = "A fusion of elegance and modernity. Balanced serif and hybrid fonts evoking both magic and science.",
  fonts = "Spectral, Literata 72pt, Crimson Pro, IBM Plex Serif, Bitter Pro, Rosarivo",
  presets = {
    { font = "Spectral", size = 10.0, weight = 0.625, line_spacing_percent = 104, line_spacing_em = "1.25em" },
    { font = "Literata 72pt", size = 10.1, weight = 0.5, line_spacing_percent = 106, line_spacing_em = "1.25em" },
    { font = "Crimson Pro", size = 10.0, weight = 0.5, line_spacing_percent = 104, line_spacing_em = "1.2em" },
    { font = "IBM Plex Serif", size = 9.8, weight = 0.625, line_spacing_percent = 100, line_spacing_em = "1.2em" },
    { font = "Bitter Pro", size = 9.9, weight = 0.5, line_spacing_percent = 102, line_spacing_em = "1.2em" },
    { font = "Rosarivo", size = 10.3, weight = 0.5, line_spacing_percent = 106, line_spacing_em = "1.25em" },
  }
}, ["Thriller"] = {
    description = "Tight, direct, tense. Clear sans-serif fonts that maintain urgency without coldness.",
    fonts = "Bitter Pro, Atkinson Hyperlegible, Crimson Pro, Spectral, Literata 72pt, Lexend",
    presets = {
      { font = "Bitter Pro", size = 10.0, weight = 0.625, line_spacing_percent = 100, line_spacing_em = "1.2em" },
      { font = "Atkinson Hyperlegible", size = 10.2, weight = 0.5, line_spacing_percent = 102, line_spacing_em = "1.2em" },
      { font = "Crimson Pro", size = 9.8, weight = 0.5, line_spacing_percent = 104, line_spacing_em = "1.25em" },
      { font = "Spectral", size = 10.0, weight = 0.625, line_spacing_percent = 98, line_spacing_em = "1.15em" },
      { font = "Literata 72pt", size = 10.1, weight = 0.5, line_spacing_percent = 102, line_spacing_em = "1.2em" },
      { font = "Lexend", size = 10.3, weight = 0.5, line_spacing_percent = 100, line_spacing_em = "1.2em" },
    }
  },  ["Horror"] = {
    description = "Traditional serif fonts with a decadent, sometimes poetic feel. Elegant but unsettling.",
    fonts = "EB Garamond, IM FELL DW Pica, Rosarivo, Spectral, Garamond Libre, Crimson Pro",
    presets = {
      { font = "EB Garamond", size = 9.9, weight = 0.5, line_spacing_percent = 113, line_spacing_em = "1.35em" },
      { font = "IM FELL DW Pica", size = 10.6, weight = 0.3, line_spacing_percent = 117, line_spacing_em = "1.4em" },
      { font = "Rosarivo", size = 10.0, weight = 0.375, line_spacing_percent = 113, line_spacing_em = "1.35em" },
      { font = "Spectral", size = 9.7, weight = 0.625, line_spacing_percent = 109, line_spacing_em = "1.3em" },
      { font = "Garamond Libre", size = 10.2, weight = 0.5, line_spacing_percent = 113, line_spacing_em = "1.35em" },
      { font = "Crimson Pro", size = 9.9, weight = 0.625, line_spacing_percent = 109, line_spacing_em = "1.3em" },
    }
  },  ["Historical Fantasy"] = {
    description = "Readable but classic-looking serif fonts. Clear and spacious for immersive prose.",
    fonts = "Literata 72pt, Cardo, Libre Caslon, Cormorant Garamond, Spectral, Rosarivo",
    presets = {
      { font = "Literata 72pt", size = 10.0, weight = 0.5, line_spacing_percent = 105, line_spacing_em = "1.25em" },
      { font = "Cardo", size = 10.6, weight = 0.5, line_spacing_percent = 108, line_spacing_em = "1.3em" },
      { font = "Libre Caslon", size = 10.4, weight = 0.375, line_spacing_percent = 106, line_spacing_em = "1.25em" },
      { font = "Cormorant Garamond", size = 10.0, weight = 0.5, line_spacing_percent = 102, line_spacing_em = "1.2em" },
      { font = "Spectral", size = 10.2, weight = 0.625, line_spacing_percent = 100, line_spacing_em = "1.2em" },
      { font = "Rosarivo", size = 10.3, weight = 0.5, line_spacing_percent = 104, line_spacing_em = "1.25em" },
    }
  },  ["Contemporary"] = {
    description = "Neutral, modern, and straightforward fonts. Comfortable for day-to-day reading.",
    fonts = "Source Sans Pro, Inter, FiraGO, Lexend, Bitter Pro, Crimson Pro",
    presets = {
      { font = "Source Sans Pro", size = 9.9, weight = 0.5, line_spacing_percent = 100, line_spacing_em = "1.2em" },
      { font = "Inter", size = 9.8, weight = 0.5, line_spacing_percent = 100, line_spacing_em = "1.2em" },
      { font = "FiraGO", size = 9.9, weight = 0.5, line_spacing_percent = 104, line_spacing_em = "1.25em" },
      { font = "Lexend", size = 9.9, weight = 0.5, line_spacing_percent = 96, line_spacing_em = "1.15em" },
      { font = "Bitter Pro", size = 10.0, weight = 0.625, line_spacing_percent = 104, line_spacing_em = "1.25em" },
      { font = "Crimson Pro", size = 10.0, weight = 0.5, line_spacing_percent = 100, line_spacing_em = "1.2em" },
    }
  },  ["Non-Fiction"] = {
    description = "Professional, neutral fonts prioritizing clarity, structure and focus.",
    fonts = "Georgia, Merriweather, Cardo, Libre Caslon, Spectral, Source Serif Pro",
    presets = {
      { font = "Georgia", size = 10.0, weight = 0.5, line_spacing_percent = 100, line_spacing_em = "1.2em" },
      { font = "Merriweather", size = 10.1, weight = 0.5, line_spacing_percent = 104, line_spacing_em = "1.25em" },
      { font = "Cardo", size = 10.2, weight = 0.5, line_spacing_percent = 104, line_spacing_em = "1.25em" },
      { font = "Libre Caslon", size = 10.0, weight = 0.375, line_spacing_percent = 109, line_spacing_em = "1.3em" },
      { font = "Spectral", size = 9.9, weight = 0.5, line_spacing_percent = 100, line_spacing_em = "1.2em" },
      { font = "Source Serif Pro", size = 10.1, weight = 0.5, line_spacing_percent = 100, line_spacing_em = "1.2em" },
    }
  },  ["Dystopia"] = {
    description = "Compact fonts evoking a sense of control, oppression or minimalism.",
    fonts = "FiraGO, Atkinson Hyperlegible, Lexend, Inter, Bitter Pro, IBM Plex Sans",
    presets = {
      { font = "FiraGO", size = 10.0, weight = 0.5, line_spacing_percent = 98, line_spacing_em = "1.15em" },
      { font = "Atkinson Hyperlegible", size = 10.4, weight = 0.5, line_spacing_percent = 106, line_spacing_em = "1.25em" },
      { font = "Lexend", size = 10.0, weight = 0.5, line_spacing_percent = 100, line_spacing_em = "1.2em" },
      { font = "Inter", size = 9.9, weight = 0.5, line_spacing_percent = 100, line_spacing_em = "1.2em" },
      { font = "Bitter Pro", size = 10.2, weight = 0.625, line_spacing_percent = 101, line_spacing_em = "1.2em" },
      { font = "IBM Plex Sans", size = 9.8, weight = 0.625, line_spacing_percent = 98, line_spacing_em = "1.15em" },
    }
  },  ["Young Adult"] = {
    description = "Accessible, fresh and easy-to-read sans fonts. Open curves and modern rhythm.",
    fonts = "Lexend, Atkinson Hyperlegible, FiraGO, Bitter Pro, Source Sans Pro, Inter",
    presets = {
      { font = "Lexend", size = 9.8, weight = 0.5, line_spacing_percent = 96, line_spacing_em = "1.15em" },
      { font = "Atkinson Hyperlegible", size = 10.0, weight = 0.5, line_spacing_percent = 100, line_spacing_em = "1.2em" },
      { font = "FiraGO", size = 10.0, weight = 0.5, line_spacing_percent = 100, line_spacing_em = "1.2em" },
      { font = "Bitter Pro", size = 9.8, weight = 0.625, line_spacing_percent = 104, line_spacing_em = "1.25em" },
      { font = "Source Sans Pro", size = 9.9, weight = 0.5, line_spacing_percent = 96, line_spacing_em = "1.15em" },
      { font = "Inter", size = 10.0, weight = 0.5, line_spacing_percent = 100, line_spacing_em = "1.2em" },
    }
  },
}
