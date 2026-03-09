//
//  input_osk.c
//  RetroArch
//
//  Created by haharsw on 2025/10/3.
//

#include <input/input_osk.h>
#include <input/input_driver.h>

bool input_keyboard_line_event(input_driver_state_t *input_st, input_keyboard_line_t *state, uint32_t character);

void input_event_osk_append(
      input_keyboard_line_t *keyboard_line,
      enum osk_type *osk_idx,
      unsigned *osk_last_codepoint,
      unsigned *osk_last_codepoint_len,
      int ptr,
      bool show_symbol_pages,
      const char *word,
      size_t len)
{
#ifdef HAVE_LANGEXTRA
   if (string_is_equal(word, "\xe2\x87\xa6")) /* backspace character */
      input_keyboard_event(true, '\x7f', '\x7f', 0, RETRO_DEVICE_KEYBOARD);
   else if (string_is_equal(word, "\xe2\x8f\x8e")) /* return character */
      input_keyboard_event(true, '\n', '\n', 0, RETRO_DEVICE_KEYBOARD);
   else
   if (string_is_equal(word, "\xe2\x87\xa7")) /* up arrow */
      *osk_idx = OSK_UPPERCASE_LATIN;
   else if (string_is_equal(word, "\xe2\x87\xa9")) /* down arrow */
      *osk_idx = OSK_LOWERCASE_LATIN;
   else if (string_is_equal(word,"\xe2\x8a\x95")) /* plus sign (next button) */
   {
      if (*msg_hash_get_uint(MSG_HASH_USER_LANGUAGE) == RETRO_LANGUAGE_KOREAN   )
      {
         static int prv_osk = OSK_TYPE_UNKNOWN+1;
         if (*osk_idx < OSK_KOREAN_PAGE1 )
         {
            prv_osk = *osk_idx;
            *osk_idx =  OSK_KOREAN_PAGE1;
         }
         else
            *osk_idx = (enum osk_type)prv_osk;
      }
      else
      if (*osk_idx < (show_symbol_pages ? OSK_TYPE_LAST - 1 : OSK_SYMBOLS_PAGE1))
         *osk_idx = (enum osk_type)(*osk_idx + 1);
      else
         *osk_idx = ((enum osk_type)(OSK_TYPE_UNKNOWN + 1));
   }
   else if (*osk_idx == OSK_KOREAN_PAGE1 && word && len == 3)
   {
      input_driver_state_t *input_st = input_state_get_ptr();
      unsigned character             = *((unsigned*)word) | 0x01000000;
      input_keyboard_line_event(input_st,  keyboard_line, character);
   }
#else
   if (string_is_equal(word, "Bksp"))
      input_keyboard_event(true, '\x7f', '\x7f', 0, RETRO_DEVICE_KEYBOARD);
   else if (string_is_equal(word, "Enter"))
      input_keyboard_event(true, '\n', '\n', 0, RETRO_DEVICE_KEYBOARD);
   else
   if (string_is_equal(word, "Upper"))
      *osk_idx = OSK_UPPERCASE_LATIN;
   else if (string_is_equal(word, "Lower"))
      *osk_idx = OSK_LOWERCASE_LATIN;
   else if (string_is_equal(word, "Next"))
      if (*osk_idx < (show_symbol_pages ? OSK_TYPE_LAST - 1 : OSK_SYMBOLS_PAGE1))
         *osk_idx = (enum osk_type)(*osk_idx + 1);
      else
         *osk_idx = ((enum osk_type)(OSK_TYPE_UNKNOWN + 1));
#endif
   else
   {
      input_keyboard_line_append(keyboard_line, word, len);
      osk_update_last_codepoint(
            osk_last_codepoint,
            osk_last_codepoint_len,
            word);
   }
}

void osk_update_last_codepoint(
      unsigned *last_codepoint,
      unsigned *last_codepoint_len,
      const char *word)
{
   const char *letter         = word;
   const char    *pos         = letter;

   if (word[0] == 0)
   {
      *last_codepoint         = 0;
      *last_codepoint_len     = 0;
      return;
   }

   for (;;)
   {
      unsigned codepoint      = utf8_walk(&letter);
      if (letter[0] == 0)
      {
         *last_codepoint      = codepoint;
         *last_codepoint_len  = (unsigned)(letter - pos);
         break;
      }
      pos                     = letter;
   }
}
