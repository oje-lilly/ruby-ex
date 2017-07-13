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

#include "drmaa2.h"

int main(int argc, char **argv) {

   drmaa2_jsession js = NULL;

   js = drmaa2_create_jsession("howto1_session", NULL);

   if (js == NULL) {
      char* error_text = drmaa2_lasterror_text();
      fprintf(stderr, "Could not create/open DRMAA2 job session (%s).\n", error_text);
      drmaa2_string_free(&error_text);
      return 1;
   } else {
      drmaa2_error error;
      drmaa2_string sn = drmaa2_jsession_get_session_name(js);

      fprintf(stdout, "Created and opened persistent job session (%s) successfully.\n", sn);
      drmaa2_string_free(&sn);

      error = drmaa2_close_jsession(js);
      if (error != DRMAA2_SUCCESS) {
         char* error_text = drmaa2_lasterror_text();
         fprintf(stderr, "Could not close job session (%s).\n", error_text);
         drmaa2_string_free(&error_text);
      } else {
         fprintf(stdout, "Successfully closed job session.\n");
      }

      drmaa2_jsession_free(&js);
      error = drmaa2_destroy_jsession("howto1_session");
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

