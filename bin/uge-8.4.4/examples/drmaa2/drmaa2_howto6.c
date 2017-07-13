/*___INFO__MARK_BEGIN__*/
/*****************************************************************************
 *
 *  The contents of this file are made available subject to the terms of the
 *  Apache Software License 2.0 ('The License').
 *  You may not use this file except in compliance with The License.
 *  You may obtain a copy of The License at
 *  http://www.apache.org/licenses/LICENSE-2.0.html
 *
 *  Copyright (c) 2013 Univa Corporation.
 *
 ****************************************************************************/
/*___INFO__MARK_END__*/

#include <stdio.h>
#include <string.h>

#include "drmaa2.h"

/**
 * @brief Checks support of a given DRMAA2 capability and prints result to stdout.
 *
 * @param name The name of the capability as string.
 * @param cap The capability to test.
 */
static void check_capability(const char* name, const drmaa2_capability cap) {
   if (drmaa2_supports(cap) == DRMAA2_TRUE) {
      fprintf(stdout, "DRMAA2 library supports %s\n", name);
   } else {
      fprintf(stdout, "DRMAA2 library does not support %s\n", name);
   }
}

/**
 * @brief Prints a DRMAA2 string list to stdout.
 *
 * @param list The list to print
 */
static void print_string_list(const char* listname, drmaa2_string_list list) {

   fprintf(stdout, "%s: ", listname);

   if (list == NULL) {
      fprintf(stdout, "List is NULL.\n");
   } else {
      size_t i, size = drmaa2_list_size(list);
      if (size == 0) {
         fprintf(stdout, "List is empty.\n");
      } else {
         for (i = 0; i < size; i++) {
            fprintf(stdout, "%s ", (char *) drmaa2_list_get(list, i));
         }
         fprintf(stdout, "\n");
      }
   }
}

int main(int argc, char **argv) {
   drmaa2_string name;
   drmaa2_version version;
   drmaa2_string_list jsl;
  
   jsl = drmaa2_get_jsession_names();
   fprintf(stdout, "Following DRMAA2 job sessions are available: ");
   if (jsl != NULL) {
      size_t i, size = drmaa2_list_size(jsl);
      for (i = 0; i < size; i++) {
         fprintf(stdout, "%s ", (char *) drmaa2_list_get(jsl, i));
      }
   }
   fprintf(stdout, "\n");
   drmaa2_list_free(&jsl);

   name = drmaa2_get_drms_name();
   if (name != NULL) {
      fprintf(stdout, "The name of the DRMS is %s.\n", name);
   } else {
      fprintf(stderr, "The name of the DRMS was not set.\n");
   }
   drmaa2_string_free(&name);

   version = drmaa2_get_drms_version();
   if (version == NULL) {
      fprintf(stdout, "No version reported by DRMAA2 library.\n");
   } else {
      fprintf(stderr, "The version of the DRMS is %s.%s.\n", version->major, version->minor); 
   }
   drmaa2_version_free(&version);

   /* Check DRMAA2 implementation capabilities */
   check_capability("DRMAA2_ADVANCE_RESERVATION", DRMAA2_ADVANCE_RESERVATION);
   check_capability("DRMAA2_RESERVE_SLOTS", DRMAA2_RESERVE_SLOTS);
   check_capability("DRMAA2_CALLBACK", DRMAA2_CALLBACK);
   check_capability("DRMAA2_BULK_JOBS_MAXPARALLEL", DRMAA2_BULK_JOBS_MAXPARALLEL);
   check_capability("DRMAA2_JT_EMAIL", DRMAA2_JT_EMAIL);
   check_capability("DRMAA2_JT_STAGING", DRMAA2_JT_STAGING);
   check_capability("DRMAA2_JT_DEADLINE", DRMAA2_JT_DEADLINE);
   check_capability("DRMAA2_JT_MAXSLOTS", DRMAA2_JT_MAXSLOTS);
   check_capability("DRMAA2_JT_ACCOUNTINGID", DRMAA2_JT_ACCOUNTINGID);
   check_capability("DRMAA2_RT_STARTNOW", DRMAA2_RT_STARTNOW);
   check_capability("DRMAA2_RT_DURATION", DRMAA2_RT_DURATION);
   check_capability("DRMAA2_RT_MACHINEOS", DRMAA2_RT_MACHINEOS);
   check_capability("DRMAA2_RT_MACHINEARCH", DRMAA2_RT_MACHINEARCH);

   /* Print implementation specific enhancements */
   fprintf(stdout, "Checking implementation specific parameters for following objects:\n");
   print_string_list("jtemplate", drmaa2_jtemplate_impl_spec());
   print_string_list("jinfo", drmaa2_jinfo_impl_spec());
   print_string_list("rtemplate", drmaa2_rtemplate_impl_spec());
   print_string_list("rinfo", drmaa2_rinfo_impl_spec());
   print_string_list("queueinfo", drmaa2_queueinfo_impl_spec());
   print_string_list("machineinfo", drmaa2_machineinfo_impl_spec());
   print_string_list("notification", drmaa2_notification_impl_spec());

   return 0;
}

