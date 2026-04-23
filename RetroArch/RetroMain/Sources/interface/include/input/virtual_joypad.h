//
//  virtual_joypad.h
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

#ifndef VIRTUAL_JOYPAD_H
#define VIRTUAL_JOYPAD_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

enum virtual_joypad_axis
{
    VIRTUAL_JOYPAD_AXIS_LEFT_X  = 0,
    VIRTUAL_JOYPAD_AXIS_LEFT_Y  = 1,
    VIRTUAL_JOYPAD_AXIS_RIGHT_X = 2,
    VIRTUAL_JOYPAD_AXIS_RIGHT_Y = 3
};

void virtual_joypad_set_button(unsigned port, unsigned id, bool down);
void virtual_joypad_set_axis(unsigned port, unsigned axis, int16_t value);
void virtual_joypad_set_connected(unsigned port, bool connected);
void virtual_joypad_commit_frame_state(void);
void virtual_joypad_reset(unsigned port);
void virtual_joypad_reset_all(void);

#ifdef __cplusplus
}
#endif

#endif /* VIRTUAL_JOYPAD_H */

