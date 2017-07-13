/*___INFO__MARK_BEGIN__*/
/*****************************************************************************
 *
 *  The contents of this file are made available subject to the terms of the
 *  Apache Software License 2.0 ('The License').
 *  You may not use this file except in compliance with The License.
 *  You may obtain a copy of The License at
 *  http://www.apache.org/licenses/LICENSE-2.0.html
 *
 *  Copyright (c) 2014 Univa Corporation.
 *
 ****************************************************************************/
/*___INFO__MARK_END__*/

#include <stdio.h>
#include <string.h>

#include "drmaa2.h"

int main(int argc, char **argv) {
   drmaa2_jsession js = NULL;
   
   js = drmaa2_create_jsession("howto7_session", NULL);
   if (js == NULL) {
      char* error_text = drmaa2_lasterror_text();
      fprintf(stderr, "Could not create/open DRMAA2 job session (%s).\n", error_text);
      drmaa2_string_free(&error_text);
      return 1;
   } else {
      drmaa2_error error;
      drmaa2_jtemplate jt;
      drmaa2_j job;
      drmaa2_dict limits;

      fprintf(stdout, "Created and opened persistent job session (%s) successfully.\n", 
            drmaa2_jsession_get_session_name(js));

      if ((jt = drmaa2_jtemplate_create()) == NULL) {
         fprintf(stderr, "Out of memory\n");
      } else {
         drmaa2_string_list args;
         
         jt->remoteCommand = strdup("/bin/sleep");

         args = drmaa2_list_create(DRMAA2_STRINGLIST, NULL);
         if (drmaa2_list_add(args, "60") != DRMAA2_SUCCESS) {
            char* error_text = drmaa2_lasterror_text();
            fprintf(stderr, "Error when adding element to list (%s)\n.", error_text);
            drmaa2_string_free(&error_text);
         }
         jt->args = args;

         /* This is a parallel job. Hence we need to set the implementation
          * specific attribute 'uge_jt_pe' which is the selected parallel 
          * environment. */
         if (drmaa2_set_instance_value(jt, "uge_jt_pe", "mytestpe") != DRMAA2_SUCCESS) {
            char* error_text = drmaa2_lasterror_text();
            fprintf(stderr, "Error when adding element to list (%s)\n.", error_text);
            drmaa2_string_free(&error_text);
         }

         /* set the amount of required slots */
         jt->minSlots = 2; 
         jt->maxSlots = 4;

         /* request UGE memory complex "m_mem_free" */
         limits = drmaa2_dict_create(NULL);
/*          drmaa2_dict_set(limits, "m_mem_free", "100M"); */
         drmaa2_dict_set(limits, "mem_free", "100M");
         /* don't free it - it is now part of the jtemplate */
/*          jt->resourceLimits = limits; */

         job = drmaa2_jsession_run_job(js, jt);

         if (job == NULL) {
            char* error_text = drmaa2_lasterror_text();
            fprintf(stderr, "Error during job submission (%s)\n.", error_text);
            drmaa2_string_free(&error_text);
         } else {
            /*
            char* jid = drmaa2_j_get_id(job);
            fprintf(stdout, "Job has been submitted with id %s\n", jid);

            if (drmaa2_j_terminate(job) != DRMAA2_SUCCESS) {
               char* error_text = drmaa2_lasterror_text();
               fprintf(stderr, "Error when triggering job termination (%s)\n.", error_text);
               drmaa2_string_free(&error_text);
            } else {
               fprintf(stdout, "Sucessfully triggered job termination.\n");
            }
            drmaa2_j_free(&job);
            */
         }
         drmaa2_jtemplate_free(&jt);
      }

      error = drmaa2_close_jsession(js);
      if (error != DRMAA2_SUCCESS) {
         char* error_text = drmaa2_lasterror_text();
         fprintf(stderr, "Could not close job session (%s).\n", error_text);
         drmaa2_string_free(&error_text);
      } else {
         fprintf(stdout, "Successfully closed job session.\n");
      }

      drmaa2_jsession_free(&js);
      error = drmaa2_destroy_jsession("howto7_session");
      if (error != DRMAA2_SUCCESS) {
         char* error_text = drmaa2_lasterror_text();
         fprintf(stderr, "Could not destroy persistent job session (%s).\n", error_text);
         drmaa2_string_free(&error_text);
         return 1;
      } else {
         fprintf(stdout, "Successfully destroyed persistent job session\n"); 
      }
   }

   return 0;
}

