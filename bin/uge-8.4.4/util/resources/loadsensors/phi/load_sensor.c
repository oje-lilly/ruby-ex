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
#include <limits.h>

#include "mic_help.h"

#define MAX_STRING 1024

static void print_help() {
   printf("\n\tUsage: load_sensor [-c <config_file> | -a]\n");
   printf("\tWithout parameter the load_sensor report the default values.\n");
   printf("\t-a forces the load sensor to report all values\n");
   printf("\t-c <config_file> forces the load sensor to report the values given in the config file.\n");
   printf("\t The config_file contains a space separated list of metrics to be reported.\n");
   printf("\t Following metrics are valid: memory_utilization die_temperature board_temperature mem_temperature inlet_temperature outlet_temperature fanstatus powerusage powerlimit_physical powerlimit_upper_threshold powerlimit_lower_threshold flash_version driver_version uos_version ecc_state active_cores\n");
}

int main(int argc, char *argv[]) {
   char localHostName[MAX_STRING];

   /* first get hostname */

   /* SGE_ROOT is set, doing a system call
    * $SGE_ROOT/utilbin/lx-amd64/gethostname -aname */
   gethostname(localHostName, MAX_STRING);

   /* read config file */
   if (argc == 2) {
      if (strcmp(argv[1], "-a") == 0) {
         turn_load_values_on();
      } else if (strcmp(argv[1], "--help") == 0 ||
             strcmp(argv[1], "-help") == 0 ||
             strcmp(argv[1], "-h") == 0) {
         print_help();
         exit(0);
      } else {
         print_help();
         exit(1);
      }
   } else if (argc == 3) {
      if (strcmp(argv[1], "-c") != 0) {
         print_help();
         exit(1);
      }
      // read in config file
      read_config_and_set_value(argv[2]);
   }

   while (1) {
      char inbuf[MAX_STRING];
      size_t inlen;

      if (fgets(inbuf, MAX_STRING, stdin) == NULL) {
         break;
      }

      /* Force a NULL terminator to prevent any chance of buffer overflow */
      inbuf[MAX_STRING - 1] = '\0';

      inlen = strlen(inbuf);

      if ((inlen == 5) && strncasecmp(inbuf, "quit", inlen - 1) == 0) {
         break;
      }

      printf("begin\n");

      load_sensor(localHostName, -1);

      printf("end\n");
      fflush(stdout);
   }
}


