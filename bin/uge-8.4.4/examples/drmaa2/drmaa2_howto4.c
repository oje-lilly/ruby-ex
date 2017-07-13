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

int main(int argc, char **argv) {
   drmaa2_jsession js = NULL;
   
   js = drmaa2_create_jsession("howto4_session", NULL);
   if (js == NULL) {
      char* error_text = drmaa2_lasterror_text();
      fprintf(stderr, "Could not create/open DRMAA2 job session (%s).\n", error_text);
      drmaa2_string_free(&error_text);
      return 1;
   } else {
      drmaa2_error error;
      drmaa2_jtemplate jt;
      drmaa2_j job;

      fprintf(stdout, "Created and opened persistent job session (%s) successfully.\n", 
            drmaa2_jsession_get_session_name(js));

      if ((jt = drmaa2_jtemplate_create()) == NULL) {
         fprintf(stderr, "Out of memory\n");
      } else {
         drmaa2_string_list args;
         
         jt->remoteCommand = strdup("/bin/sleep");

         args = drmaa2_list_create(DRMAA2_STRINGLIST, NULL);
         if (drmaa2_list_add(args, "60") != DRMAA2_SUCCESS) {
            char* error_text = NULL;
            fprintf(stderr, "Error when adding element to list (%s)\n.", error_text);
            drmaa2_string_free(&error_text);
         }
         jt->args = args;

         job = drmaa2_jsession_run_job(js, jt);
         if (job == NULL) {
            char* error_text = drmaa2_lasterror_text();
            fprintf(stderr, "Error during job submission (%s)\n.", error_text);
            drmaa2_string_free(&error_text);
         } else {
            char* jid = drmaa2_j_get_id(job);
            fprintf(stdout, "Job has been submitted with id %s\n", jid);

            /* Terminate job */
            if (drmaa2_j_terminate(job) != DRMAA2_SUCCESS) {
               char* error_text = drmaa2_lasterror_text();
               fprintf(stderr, "Error when triggering job termination (%s)\n.", error_text);
               drmaa2_string_free(&error_text);
            } else {
               fprintf(stdout, "Sucessfully triggered job termination.\n");
            }
            drmaa2_j_free(&job);
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
      error = drmaa2_destroy_jsession("howto4_session");
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

