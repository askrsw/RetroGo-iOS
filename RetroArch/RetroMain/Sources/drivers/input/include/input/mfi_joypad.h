#ifndef INPUT_MFI_JOYPAD_H__
#define INPUT_MFI_JOYPAD_H__

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*mfi_joypad_button_event_callback_t)(unsigned port, uint16_t joykey, bool pressed, const char *display_name, void *userdata);
typedef void (*mfi_joypad_axis_event_callback_t)(unsigned port, uint32_t joyaxis, int16_t axis_value, bool pressed, const char *display_name, void *userdata);
typedef bool (*mfi_joypad_button_suppression_callback_t)(unsigned port, uint16_t joykey, void *userdata);
typedef bool (*mfi_joypad_axis_suppression_callback_t)(unsigned port, uint32_t joyaxis, void *userdata);

void mfi_joypad_set_button_event_callback(mfi_joypad_button_event_callback_t callback, void *userdata);
void mfi_joypad_set_axis_event_callback(mfi_joypad_axis_event_callback_t callback, void *userdata);
void mfi_joypad_set_button_suppression_callback(mfi_joypad_button_suppression_callback_t callback, void *userdata);
void mfi_joypad_set_axis_suppression_callback(mfi_joypad_axis_suppression_callback_t callback, void *userdata);

void mfi_joypad_start_button_event_monitor(void);
void mfi_joypad_stop_button_event_monitor(void);

typedef void (*mfi_joypad_topology_changed_callback_t)(void *userdata);
void mfi_joypad_set_topology_changed_callback(mfi_joypad_topology_changed_callback_t callback, void *userdata);
void mfi_joypad_notify_auto_binds_changed(unsigned port);
#ifdef __cplusplus
}
#endif

#endif
