//
//  language_manager.c
//  RetroArch
//
//  Created by haharsw on 2025/10/5.
//

#include <intl/language_manager.h>

/* TODO/FIXME - static public global variable */
static unsigned uint_user_language;

enum retro_language retroarch_get_language_from_iso(const char *iso639)
{
   unsigned i;
   enum retro_language lang = RETRO_LANGUAGE_ENGLISH;

   struct lang_pair
   {
      const char *iso639;
      enum retro_language lang;
   };

   const struct lang_pair pairs[] =
   {
      {"ja", RETRO_LANGUAGE_JAPANESE},
      {"fr", RETRO_LANGUAGE_FRENCH},
      {"es", RETRO_LANGUAGE_SPANISH},
      {"de", RETRO_LANGUAGE_GERMAN},
      {"it", RETRO_LANGUAGE_ITALIAN},
      {"nl", RETRO_LANGUAGE_DUTCH},
      {"pt_BR", RETRO_LANGUAGE_PORTUGUESE_BRAZIL},
      {"pt_PT", RETRO_LANGUAGE_PORTUGUESE_PORTUGAL},
      {"pt", RETRO_LANGUAGE_PORTUGUESE_PORTUGAL},
      {"ru", RETRO_LANGUAGE_RUSSIAN},
      {"ko", RETRO_LANGUAGE_KOREAN},
      {"zh_CN", RETRO_LANGUAGE_CHINESE_SIMPLIFIED},
      {"zh_SG", RETRO_LANGUAGE_CHINESE_SIMPLIFIED},
      {"zh_HK", RETRO_LANGUAGE_CHINESE_TRADITIONAL},
      {"zh_TW", RETRO_LANGUAGE_CHINESE_TRADITIONAL},
      {"zh", RETRO_LANGUAGE_CHINESE_SIMPLIFIED},
      {"eo", RETRO_LANGUAGE_ESPERANTO},
      {"pl", RETRO_LANGUAGE_POLISH},
      {"vi", RETRO_LANGUAGE_VIETNAMESE},
      {"ar", RETRO_LANGUAGE_ARABIC},
      {"el", RETRO_LANGUAGE_GREEK},
      {"tr", RETRO_LANGUAGE_TURKISH},
      {"sk", RETRO_LANGUAGE_SLOVAK},
      {"fa", RETRO_LANGUAGE_PERSIAN},
      {"he", RETRO_LANGUAGE_HEBREW},
      {"ast", RETRO_LANGUAGE_ASTURIAN},
      {"fi", RETRO_LANGUAGE_FINNISH},
      {"id", RETRO_LANGUAGE_INDONESIAN},
      {"sv", RETRO_LANGUAGE_SWEDISH},
      {"uk", RETRO_LANGUAGE_UKRAINIAN},
      {"cs", RETRO_LANGUAGE_CZECH},
      {"ca_ES@valencia", RETRO_LANGUAGE_CATALAN_VALENCIA},
      {"en_CA", RETRO_LANGUAGE_BRITISH_ENGLISH}, /* Canada must be indexed before Catalan's "ca". */
      {"ca", RETRO_LANGUAGE_CATALAN},
      {"en_GB", RETRO_LANGUAGE_BRITISH_ENGLISH},
      {"en", RETRO_LANGUAGE_ENGLISH},
      {"hu", RETRO_LANGUAGE_HUNGARIAN},
      {"be", RETRO_LANGUAGE_BELARUSIAN},
      {"gl", RETRO_LANGUAGE_GALICIAN},
      {"no", RETRO_LANGUAGE_NORWEGIAN},
      {"ga", RETRO_LANGUAGE_IRISH},
   };

   if (string_is_empty(iso639))
      return lang;

   for (i = 0; i < ARRAY_SIZE(pairs); i++)
   {
      if (string_starts_with_case_insensitive(iso639, pairs[i].iso639))
      {
         lang = pairs[i].lang;
         break;
      }
   }

   return lang;
}

const char *get_user_language_iso639_1(bool limit)
{
   switch (uint_user_language)
   {
      case RETRO_LANGUAGE_FRENCH:
         return "fr";
      case RETRO_LANGUAGE_GERMAN:
         return "de";
      case RETRO_LANGUAGE_SPANISH:
         return "es";
      case RETRO_LANGUAGE_ITALIAN:
         return "it";
      case RETRO_LANGUAGE_PORTUGUESE_BRAZIL:
         if (limit)
            return "pt";
         return "pt_br";
      case RETRO_LANGUAGE_PORTUGUESE_PORTUGAL:
         if (limit)
            return "pt";
         return "pt_pt";
      case RETRO_LANGUAGE_DUTCH:
         return "nl";
      case RETRO_LANGUAGE_ESPERANTO:
         return "eo";
      case RETRO_LANGUAGE_POLISH:
         return "pl";
      case RETRO_LANGUAGE_JAPANESE:
         return "ja";
      case RETRO_LANGUAGE_KOREAN:
         return "ko";
      case RETRO_LANGUAGE_VIETNAMESE:
         return "vi";
      case RETRO_LANGUAGE_CHINESE_SIMPLIFIED:
         if (limit)
            return "zh";
         return "zh_cn";
      case RETRO_LANGUAGE_CHINESE_TRADITIONAL:
         if (limit)
            return "zh";
         return "zh_tw";
      case RETRO_LANGUAGE_ARABIC:
         return "ar";
      case RETRO_LANGUAGE_GREEK:
         return "el";
      case RETRO_LANGUAGE_TURKISH:
         return "tr";
      case RETRO_LANGUAGE_SLOVAK:
         return "sk";
      case RETRO_LANGUAGE_RUSSIAN:
         return "ru";
      case RETRO_LANGUAGE_PERSIAN:
         return "fa";
      case RETRO_LANGUAGE_HEBREW:
         return "he";
      case RETRO_LANGUAGE_ASTURIAN:
         return "ast";
      case RETRO_LANGUAGE_FINNISH:
         return "fi";
      case RETRO_LANGUAGE_INDONESIAN:
         return "id";
      case RETRO_LANGUAGE_SWEDISH:
         return "sv";
      case RETRO_LANGUAGE_UKRAINIAN:
         return "uk";
      case RETRO_LANGUAGE_CZECH:
         return "cs";
      case RETRO_LANGUAGE_CATALAN_VALENCIA:
         if (limit)
            return "ca";
         return "ca_ES@valencia";
      case RETRO_LANGUAGE_CATALAN:
         return "ca";
      case RETRO_LANGUAGE_BRITISH_ENGLISH:
         if (limit)
            return "en";
         return "en_gb";
      case RETRO_LANGUAGE_HUNGARIAN:
         return "hu";
      case RETRO_LANGUAGE_BELARUSIAN:
         return "be";
      case RETRO_LANGUAGE_GALICIAN:
          return "gl";
      case RETRO_LANGUAGE_NORWEGIAN:
          return "no";
      case RETRO_LANGUAGE_IRISH:
          return "ga";
   }
   return "en";
}

unsigned *msg_hash_get_uint(enum msg_hash_action type)
{
   switch (type)
   {
      case MSG_HASH_USER_LANGUAGE:
         return &uint_user_language;
      case MSG_HASH_NONE:
         break;
   }

   return NULL;
}

void msg_hash_set_uint(enum msg_hash_action type, unsigned val)
{
   switch (type)
   {
      case MSG_HASH_USER_LANGUAGE:
         uint_user_language = val;
         break;
      case MSG_HASH_NONE:
         break;
   }
}
