//
//  RAPhoneRumble.h
//  RetroGo
//
//  Created by haharsw on 2026/10/9.
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

#ifndef RA_PHONE_RUMBLE_H
#define RA_PHONE_RUMBLE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Plays the rumble a core requests on the phone's own Taptic Engine, for the
 * player on the on-screen controls. A pad whose physical controller has motors
 * rumbles there instead (mfi_joypad), never on the phone as well.
 *
 * The strong motor is a low, dull rumble and the weak one a finer buzz, both
 * continuous; a request only changes their intensity, so cores that fade a
 * rumble frame by frame play smoothly.
 */

/* Any thread; called by the virtual joypad for every request a core makes.
 * effect is enum retro_rumble_effect (0 strong, 1 weak), strength 0...65535. */
void ra_phone_rumble_set_state(unsigned pad, unsigned effect, uint16_t strength);

/* The game's rumble setting; off stops the phone at once. */
void ra_phone_rumble_set_enabled(bool enabled);

/* Pause and resume of the game: a paused core stops sending requests, so a
 * rumble left on would never end. Resume plays the last requested state. */
void ra_phone_rumble_suspend(void);
void ra_phone_rumble_resume(void);

/* A game starts or ends: forget every request and release the engine. */
void ra_phone_rumble_reset(void);

#ifdef __cplusplus
}
#endif

#endif /* RA_PHONE_RUMBLE_H */
