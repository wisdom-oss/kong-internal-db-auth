local typedefs = require "kong.db.schema.typedefs"

return {
    name = "kong-internal-db-auth",
    fields = {
        {
            consumer = typedefs.no_consumer
        },
        {
            protocols = typedefs.protocols_http
        },
        {
            config = {
                type = "record",
                fields = {
                    {intospection_url = {
                        type = "string",
                        required = true
                    }},
                    {auth_header = {
                        type = "string",
                        required = true
                    }}
                }
            }
        }
    }
}