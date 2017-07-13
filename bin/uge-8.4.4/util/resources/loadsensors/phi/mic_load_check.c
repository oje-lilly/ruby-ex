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
/* phi_load_sensor.c */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#include "mic_help.h"

#define MAX_STRING 1024

#define true  1
#define false 0

static void print_help() {
   printf("\n\tUsage: [-h | -a | -amount | [-mic <number] -p <param_list>]\n");
   printf("\tWithout parameter the tool reports default values for all Intel Xeon Phi.\n");
   printf("\t-h              Print this help.\n");
   printf("\t-a              The tools reports all values.\n");
   printf("\t-amount         Prints the amount of Intel Xeon Phi Cards found.\n");
   printf("\t-mic <number>   Filters output for only a specific Intel Xeon Phi card.\n");
   printf("\t-p <param_list> Reports the values given in the parameter list.\n");
   printf("\t Following values are valid: memory_utilization die_temperature board_temperature mem_temperature inlet_temperature outlet_temperature fanstatus powerusage powerlimit_physical powerlimit_upper_threshold powerlimit_lower_threshold flash_version driver_version uos_version ecc_state active_cores\n");
}

/**
 * @brief Start the MIC check application.
 *
 * This application is intended for the users with MIC (Intel Xeon Phi)
 * cards installed in their clusters.
 *
 * One use case is that an application wants to decided on which Phi
 * card it wants to run, based on load values. Grid Engine can select
 * a host which offers a specific Phi card with the load values (by
 * selecting the host wich offers a Phi with least temperature for
 * example) but it can currently not redirect the application to the
 * appropriate card. Hence this application helps to get all load values
 * from the card.
 *
 * The most common approach would be that a Phi card is configured as
 * a RSMAP value, which can be selected by the scheduler. The job has
 * the selected Phi card number then in the environment. But we don't
 * want to exclude users which want to manage MIC access for themself.
 *
 * @param argc Amount of parameters
 * @param argv[] The command line parameters.
 *
 * @return 0 in case of succes otherwise 1
 */
int main(int argc, char *argv[]) {
   char localHostName[MAX_STRING];
   int card_nr = -1;

   /* read config file */
   if (argc == 2) {
      if (strcmp(argv[1], "-a") == 0) {
         /* The caller wants to see all available load values from the card. */
         turn_load_values_on();
      } else if (strcmp(argv[1], "-amount") == 0) {
         printf("%d\n", get_amount_of_cards());
         exit(0);
      } else if (strcmp(argv[1], "--help") == 0 ||
             strcmp(argv[1], "-help") == 0 ||
             strcmp(argv[1], "-h") == 0) {
         /* The user wants to see the help output. */
         print_help();
         exit(0);
      } else {
         /* The request is unknown: print help and exit with error. */
         print_help();
         exit(1);
      }
   } else if (argc >= 3) {
      int i = 0;
      int next_arg = 1;

      /* The filters output only for a specific MIC card. */
      if (strcmp(argv[next_arg], "-mic") == 0) {
         next_arg++;
         /* set filter for specific MIC card */
         card_nr = atoi(argv[next_arg]);
         next_arg++;
      }

      if (next_arg < argc) {
         /* The user wants to have reported only a special set of load values, given after the -p request. */
         if (strcmp(argv[next_arg], "-p") != 0) {
            print_help();
            exit(1);
         }
         next_arg++;
         /* First disable the default load value selection. */
         turn_load_values_off();
         /* read in the parameters */
         for (i = next_arg; i < argc; i++) {
            /* now mark all load values the user want to have reported */
            if (check_and_mark(argv[i]) == false) {
               exit(1);
            }
         }
      }
   }
   /* Print all load values, which are activated. */
   load_sensor("", card_nr);
   exit(0);
}

