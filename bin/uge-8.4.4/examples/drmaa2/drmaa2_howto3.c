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
   
   js = drmaa2_create_jsession("howto3_session", NULL);
   
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
         if (drmaa2_list_add(args, "5") != DRMAA2_SUCCESS) {
            char* error_text = NULL;
            fprintf(stderr, "Error when adding element to list (%s).\n", error_text);
            drmaa2_string_free(&error_text);
         }
         jt->args = args;

         job = drmaa2_jsession_run_job(js, jt);
         if (job == NULL) {
            char* error_text = drmaa2_lasterror_text();
            fprintf(stderr, "Error during job submission (%s).\n", error_text);
            drmaa2_string_free(&error_text);
         } else {
            char* error_text = (char *) drmaa2_lasterror_text();
            char* jid = drmaa2_j_get_id(job);
            fprintf(stdout, "Job has been submitted with id %s.\n", jid);
            
            /* wait for end of job */
            if (drmaa2_j_wait_terminated(job, 120) != DRMAA2_SUCCESS) {
               error_text = (char *) drmaa2_lasterror_text();
               fprintf(stderr, "Error during waiting till end of job (%s).\n", error_text);
               drmaa2_string_free(&error_text);
            } else {
               drmaa2_jinfo jinfo = NULL;
               fprintf(stdout, "Job finished.\n");
               jinfo = drmaa2_j_get_info(job);
               if (jinfo == NULL) {
                  error_text = (char *) drmaa2_lasterror_text();
                  fprintf(stderr, "Error during waiting till end of job (%s).\n", error_text);
                  drmaa2_string_free(&error_text);
               } else {
                  /* Print all values of job info */
                  drmaa2_string_list additional_values = drmaa2_jinfo_impl_spec();
                  
                  fprintf(stdout, "jobId: %s\n", jinfo->jobId?jinfo->jobId:"NULL");
                  fprintf(stdout, "exitStatus: %d\n", jinfo->exitStatus);
                  fprintf(stdout, "terminatingSignal: %s\n", jinfo->terminatingSignal?jinfo->terminatingSignal:"NULL");
                  fprintf(stdout, "annotation: %s\n", jinfo->annotation?jinfo->annotation:"NULL");
                  fprintf(stdout, "jobState: ");
                  switch (jinfo->jobState) {
                     case DRMAA2_UNDETERMINED: fprintf(stdout, "DRMAA2_UNDETERMINED"); break;
                     case DRMAA2_QUEUED: fprintf(stdout, "DRMAA2_QUEUED"); break;
                     case DRMAA2_QUEUED_HELD: fprintf(stdout, "DRMAA2_QUEUED_HELD"); break;
                     case DRMAA2_RUNNING: fprintf(stdout, "DRMAA2_RUNNING"); break;
                     case DRMAA2_SUSPENDED: fprintf(stdout, "DRMAA2_SUSPENDED"); break;
                     case DRMAA2_REQUEUED: fprintf(stdout, "DRMAA2_REQUEUED"); break;
                     case DRMAA2_REQUEUED_HELD: fprintf(stdout, "DRMAA2_REQUEUED_HELD"); break;
                     case DRMAA2_DONE: fprintf(stdout, "DRMAA2_DONE"); break;
                     case DRMAA2_FAILED: fprintf(stdout, "DRMAA2_FAILED"); break;
                     default: fprintf(stdout, "Unknown jobstate"); break;
                  }
                  fprintf(stdout, "\n");
                  fprintf(stdout, "jobSubState: %s\n", jinfo->jobSubState?jinfo->jobSubState:"NULL");
                  fprintf(stdout, "allocatedMachines: ");
                  if (jinfo->allocatedMachines != NULL) {
                     size_t i, size = drmaa2_list_size(jinfo->allocatedMachines);
                     for (i = 0; i < size; i++) {
                        fprintf(stdout, "%s ", (drmaa2_string) drmaa2_list_get(jinfo->allocatedMachines, i));
                     }
                     fprintf(stdout, "\n");
                  } else {
                     fprintf(stdout, "NULL\n");
                  }
                  fprintf(stdout, "submissionMachine: %s\n", jinfo->submissionMachine?jinfo->submissionMachine:"NULL");
                  fprintf(stdout, "jobOwner: %s\n", jinfo->jobOwner?jinfo->jobOwner:"NULL");
                  fprintf(stdout, "slots: %lld\n", jinfo->slots);
                  fprintf(stdout, "queueName: %s\n", jinfo->queueName?jinfo->queueName:"NULL");
                  fprintf(stdout, "wallclockTime: %lld\n", (long long) jinfo->wallclockTime);
                  fprintf(stdout, "cpuTime: %lld\n", jinfo->cpuTime);
                  fprintf(stdout, "submissionTime: %lld\n", (long long) jinfo->submissionTime);
                  fprintf(stdout, "dispatchTime: %lld\n", (long long) jinfo->dispatchTime);
                  fprintf(stdout, "finishTime: %lld\n", (long long) jinfo->finishTime);

                  if (additional_values != NULL) {
                     size_t i, size = drmaa2_list_size(additional_values);
                     fprintf(stdout, "Following additional job information is supported by the DRMAA2 library: \n");
                     for (i = 0; i < size; i++) {
                        fprintf(stdout, "   %s=", (char *) drmaa2_list_get(additional_values, i));
                        fprintf(stdout, "%s\n", (char *) drmaa2_get_instance_value(jinfo, drmaa2_list_get(additional_values, i)));
                     }
                  }

               }
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
      error = drmaa2_destroy_jsession("howto3_session");
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

