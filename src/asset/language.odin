package asset


Unicode_Range_Name :: enum {
    Basic_Latin,
    Latin1_Supplement,
    Latin_Extended,
    IPA,
    Spacing_Modifier_Letters,
    Combining_Diacritical_Marks,
    Greek_Coptic,
    Cyrillic,
    Cyrillic_Supplement,
    Armenian,
    Hebrew,
    Arabic,
}

unicode_ranges :: [Unicode_Range_Name][2]i32 {
    .Basic_Latin                 = {0x21, 0x7e},
    .Latin1_Supplement           = {0xa1, 0xff},
    .Latin_Extended              = {0x100, 0x24f},
    .IPA                         = {0x250, 0x2af},
    .Spacing_Modifier_Letters    = {0x2b0, 0x2ff},
    .Combining_Diacritical_Marks = {0x300, 0x36f},
    .Greek_Coptic                = {0x370, 0x3ff},
    .Cyrillic                    = {0x400, 0x4ff},
    .Cyrillic_Supplement         = {0x500, 0x52f},
    .Armenian                    = {0x530, 0x58f},
    .Hebrew                      = {0x590, 0x5ff},
    .Arabic                      = {0x600, 0x6ff},
}

Unicode_Range_Flags :: bit_set[Unicode_Range_Name]

Language :: enum {
    English,
    Spanish,
    French,
    Italian,
    German,
    Russian,
    Greek,
}

unicode_range_flags := [Language]Unicode_Range_Flags {
    .English = {.Basic_Latin},
    .Spanish = {.Basic_Latin, .Latin1_Supplement},
    .French  = {.Basic_Latin, .Latin1_Supplement, .Latin_Extended},
    .Italian = {.Basic_Latin, .Latin1_Supplement},
    .German  = {.Basic_Latin, .Latin1_Supplement, .Latin_Extended},
    .Russian = {.Cyrillic},
    .Greek   = {.Greek_Coptic},
}
