//
//  NSCalendar+Extension.m
//  RetroGo
//
//  Created by haharsw on 2026/2/11.
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

#import "NSCalendar+Extension.h"

@implementation NSCalendar (Extension)
- (BOOL)isDateInDayBeforeYesterday:(NSDate *)date {
    NSDate *startOfToday = [self startOfDayForDate:[NSDate date]];

    NSDateComponents *yesterdayComponents = [[NSDateComponents alloc] init];
    yesterdayComponents.day = -1;
    NSDate *startOfYesterday = [self dateByAddingComponents:yesterdayComponents toDate:startOfToday options:0];

    NSDateComponents *dayBeforeYesterdayComponents = [[NSDateComponents alloc] init];
    dayBeforeYesterdayComponents.day = -1;
    NSDate *startOfDayBeforeYesterday = [self dateByAddingComponents:dayBeforeYesterdayComponents toDate:startOfYesterday options:0];

    if (!startOfYesterday || !startOfDayBeforeYesterday) {
        return NO;
    }

    NSDateComponents *endOfDayComponents = [[NSDateComponents alloc] init];
    endOfDayComponents.day = 1;
    NSDate *endOfDayBeforeYesterday = [self dateByAddingComponents:endOfDayComponents toDate:startOfDayBeforeYesterday options:0];

    return ([date compare:startOfDayBeforeYesterday] != NSOrderedAscending &&
            [date compare:endOfDayBeforeYesterday] == NSOrderedAscending);
}
@end
