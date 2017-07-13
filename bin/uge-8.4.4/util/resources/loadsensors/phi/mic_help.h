#ifndef _MIC_HELP_H
#define _MIC_HELP_H

/*___INFO__MARK_BEGIN__*/
/*****************************************************************************
 *
 *  This code is the Property, a Trade Secret and the Confidential Information
 *  of Univa Corporation.
 *
 *  Copyright Univa Corporation. All Rights Reserved. Access is Restricted.
 *
 *  It is provided to you under the terms of the
 *  Univa Term Software License Agreement.
 *
 *  If you have any questions, please contact our Support Department.
 *
 *  www.univa.com
 *
 ****************************************************************************/
/*___INFO__MARK_END__*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#include "miclib.h"

void initAdapter(struct mic_device ** accessHandle, int adapter);

void closeAdapter(struct mic_device * accessHandle);

int get_amount_of_cards(void);

void load_sensor(const char * localHostName, const int card_nr);

void turn_load_values_off(void);

void turn_load_values_on(void);

bool check_and_mark(char * load_value);

void read_config_and_set_value(const char * filename);

#endif /* _MIC_HELP_H */
