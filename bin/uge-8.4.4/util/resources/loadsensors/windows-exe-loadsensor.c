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
#include <winsock2.h>

static void getnameofhost(char *name, size_t namelen)
{
   int     wsaResult;
   WSADATA wsaData;

   /*
    * in Windows, the networking component must be loaded explicitly before any
    * of its functions can be used. This seems to be some leftover from Windows 3.11
    */
   wsaResult = WSAStartup(MAKEWORD(2, 2), &wsaData);
   if (wsaResult != 0) {
      fprintf(stderr, "WSAStartup() failed with return value %d\n", wsaResult);
   } else {
      int ret;

      ret = gethostname(name, namelen);
      if (ret == SOCKET_ERROR) {
         fprintf(stderr, "gethostname() failed with WSA error value %d\n", WSAGetLastError());
      }
   }

   WSACleanup();
}

void main(void)
{
   /*
    * in Windows, a hostname may not extend 15 characters, but RFC 1035 defines
    * 255 characters for a FQDN and 64 characters for the plain hostname,
    * so this might change in future...
    */
   char hostname[256];

   /* get name of this host */
   getnameofhost(hostname, sizeof(hostname));

   while (1) {
      char input[100];

      /* read whole lines from stdin */
      fgets(input, 100, stdin);
      if (strcmp(input, "quit\n") == 0) {
         /* quit the load sensor loop */
         break;
      } else {
         /* send mark for begin of load report */
         printf("begin\n");

         /* send fake load value in format: */
         /* hostname:load_value_name:load_value */
         printf("%s:windows_test_load:1.23456\n", hostname);

         /* send mark for end of load report */
         printf("end\n");

         /*
          * flush stdout - otherwise it will not be sent to the execution
          * daemon immediately!
          */
         fflush(stdout);
      }
   }
}
