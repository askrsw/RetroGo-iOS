//
//  virtual_joypad.m
//  RetroGo
//
//  Created by haharsw on 2026/3/22.
//  Copyright © 2026 haharsw. All rights reserved.
//
//  ---------------------------------------------------------------------------------
//  This file is part of RetroGo.
//  ---------------------------------------------------------------------------------
//
//  RetroGo is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  RetroGo is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

#include <string.h>

#include <input/input_driver.h>
#include <retro_miscellaneous.h>
#include <defines/input_defines.h>

#include "virtual_joypad.h"

static input_bits_t virtual_buttons[DEFAULT_MAX_PADS];
static int16_t virtual_axes[DEFAULT_MAX_PADS][4];
static bool virtual_connected[DEFAULT_MAX_PADS];

static void virtual_joypad_init_state(void)
{
    unsigned i;
    for (i = 0; i < DEFAULT_MAX_PADS; i++)
    {
        BIT256_CLEAR_ALL(virtual_buttons[i]);
        memset(virtual_axes[i], 0, sizeof(virtual_axes[i]));
        virtual_connected[i] = false;
    }
    virtual_connected[0] = true;
}

void virtual_joypad_set_button(unsigned port, unsigned id, bool down)
{
    if (port >= DEFAULT_MAX_PADS || id >= RARCH_BIND_LIST_END)
        return;

    if (down)
        BIT256_SET(virtual_buttons[port], id);
    else
        BIT256_CLEAR(virtual_buttons[port], id);

    virtual_connected[port] = true;
}

void virtual_joypad_set_axis(unsigned port, unsigned axis, int16_t value)
{
    if (port >= DEFAULT_MAX_PADS || axis >= 4)
        return;

    if (value > 0x7fff)
        value = 0x7fff;
    if (value < -0x7fff)
        value = -0x7fff;

    virtual_axes[port][axis] = value;
    virtual_connected[port] = true;
}

void virtual_joypad_set_connected(unsigned port, bool connected)
{
    if (port >= DEFAULT_MAX_PADS)
        return;
    virtual_connected[port] = connected;
}

void virtual_joypad_reset(unsigned port)
{
    if (port >= DEFAULT_MAX_PADS)
        return;
    BIT256_CLEAR_ALL(virtual_buttons[port]);
    memset(virtual_axes[port], 0, sizeof(virtual_axes[port]));
}

void virtual_joypad_reset_all(void)
{
    unsigned i;
    for (i = 0; i < DEFAULT_MAX_PADS; i++)
        virtual_joypad_reset(i);
}

static void *virtual_joypad_init(void *data)
{
    (void)data;
    virtual_joypad_init_state();
    return (void*)-1;
}

static bool virtual_joypad_query_pad(unsigned pad)
{
    if (pad >= DEFAULT_MAX_PADS)
        return false;
    return virtual_connected[pad];
}

static void virtual_joypad_free(void)
{
    virtual_joypad_init_state();
}

static int32_t virtual_joypad_button(unsigned port, uint16_t joykey)
{
    if (port >= DEFAULT_MAX_PADS || joykey >= RARCH_BIND_LIST_END)
        return 0;
    return BIT256_GET(virtual_buttons[port], joykey) ? 1 : 0;
}

static void virtual_joypad_get_buttons(unsigned port, input_bits_t *state)
{
    if (!state)
        return;
    if (port >= DEFAULT_MAX_PADS)
    {
        BIT256_CLEAR_ALL(*state);
        return;
    }
    memcpy(state, &virtual_buttons[port], sizeof(*state));
}

static int16_t virtual_joypad_axis(unsigned port, uint32_t joyaxis)
{
    int16_t val;
    unsigned axis;

    if (port >= DEFAULT_MAX_PADS)
        return 0;
    if (joyaxis == AXIS_NONE)
        return 0;

    axis = AXIS_NEG_GET(joyaxis);
    if (axis != AXIS_DIR_NONE && axis < 4)
    {
        val = virtual_axes[port][axis];
        return (val < 0) ? val : 0;
    }

    axis = AXIS_POS_GET(joyaxis);
    if (axis != AXIS_DIR_NONE && axis < 4)
    {
        val = virtual_axes[port][axis];
        return (val > 0) ? val : 0;
    }

    return 0;
}

static int16_t virtual_joypad_state(
        rarch_joypad_info_t *joypad_info,
        const struct retro_keybind *binds,
        unsigned port)
{
    unsigned i;
    int16_t ret = 0;
    uint16_t port_idx = joypad_info ? joypad_info->joy_idx : port;

    if (port_idx >= DEFAULT_MAX_PADS)
        return 0;

    for (i = 0; i < RARCH_FIRST_CUSTOM_BIND; i++)
    {
        const uint64_t joykey  = (binds[i].joykey != NO_BTN)
            ? binds[i].joykey  : joypad_info->auto_binds[i].joykey;
        const uint32_t joyaxis = (binds[i].joyaxis != AXIS_NONE)
            ? binds[i].joyaxis : joypad_info->auto_binds[i].joyaxis;

        if ((uint16_t)joykey != NO_BTN &&
                virtual_joypad_button(port_idx, (uint16_t)joykey))
            ret |= (1 << i);
        else if (joyaxis != AXIS_NONE &&
                ((float)abs(virtual_joypad_axis(port_idx, joyaxis)) / 0x8000) >
                joypad_info->axis_threshold)
            ret |= (1 << i);
    }

    return ret;
}

static void virtual_joypad_poll(void)
{
    if (input_autoconf_binds[0][RETRO_DEVICE_ID_JOYPAD_B].joykey == NO_BTN)
    {
        unsigned i;
        for (i = 0; i < RARCH_FIRST_CUSTOM_BIND; i++)
        {
            input_autoconf_binds[0][i].joykey = i;
            input_autoconf_binds[0][i].joyaxis = AXIS_NONE;
        }

        input_autoconf_binds[0][RARCH_ANALOG_LEFT_X_PLUS].joyaxis  = AXIS_POS(0);
        input_autoconf_binds[0][RARCH_ANALOG_LEFT_X_MINUS].joyaxis = AXIS_NEG(0);
        input_autoconf_binds[0][RARCH_ANALOG_LEFT_Y_PLUS].joyaxis  = AXIS_POS(1);
        input_autoconf_binds[0][RARCH_ANALOG_LEFT_Y_MINUS].joyaxis = AXIS_NEG(1);
        input_autoconf_binds[0][RARCH_ANALOG_RIGHT_X_PLUS].joyaxis  = AXIS_POS(2);
        input_autoconf_binds[0][RARCH_ANALOG_RIGHT_X_MINUS].joyaxis = AXIS_NEG(2);
        input_autoconf_binds[0][RARCH_ANALOG_RIGHT_Y_PLUS].joyaxis  = AXIS_POS(3);
        input_autoconf_binds[0][RARCH_ANALOG_RIGHT_Y_MINUS].joyaxis = AXIS_NEG(3);
    }
}

static bool virtual_joypad_rumble(unsigned pad, enum retro_rumble_effect effect, uint16_t strength)
{
    (void)pad;
    (void)effect;
    (void)strength;
    return false;
}

static bool virtual_joypad_rumble_gain(unsigned pad, unsigned gain)
{
    (void)pad;
    (void)gain;
    return false;
}

static bool virtual_joypad_set_sensor_state(void *data, unsigned port,
        enum retro_sensor_action action, unsigned rate)
{
    (void)data;
    (void)port;
    (void)action;
    (void)rate;
    return false;
}

static float virtual_joypad_get_sensor_input(void *data, unsigned port, unsigned id)
{
    (void)data;
    (void)port;
    (void)id;
    return 0.0f;
}

static const char *virtual_joypad_name(unsigned port)
{
    (void)port;
    return "Virtual Joypad";
}

input_device_driver_t virtual_joypad = {
    virtual_joypad_init,
    virtual_joypad_query_pad,
    virtual_joypad_free,
    virtual_joypad_button,
    virtual_joypad_state,
    virtual_joypad_get_buttons,
    virtual_joypad_axis,
    virtual_joypad_poll,
    virtual_joypad_rumble,
    virtual_joypad_rumble_gain,
    virtual_joypad_set_sensor_state,
    virtual_joypad_get_sensor_input,
    virtual_joypad_name,
    "virtual"
};
