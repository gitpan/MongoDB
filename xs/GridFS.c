/*
 * This file was generated automatically by ExtUtils::ParseXS version 2.19 from the
 * contents of GridFS.xs. Do not edit this file, edit GridFS.xs instead.
 *
 *	ANY CHANGES MADE HERE WILL BE LOST! 
 *
 */

#line 1 "xs/GridFS.xs"
#include "perl_mongo.h"

/*MODULE = MongoDB::GridFS  PACKAGE = MongoDB::GridFS

PROTOTYPES: DISABLE

void
_build_xs (self, client, db)
                SV *self
                mongo::DBClientConnection *client
                const char *db
        PREINIT:
                mongo::GridFS *grid;
        CODE:
                grid = new mongo::GridFS (client, string(db));
                perl_mongo_attach_ptr_to_instance (self, (void *)grid);

        */