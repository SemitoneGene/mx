// MusicXML Class Library
// Copyright (c) by Matthew James Briggs
// Distributed under the MIT License

#pragma once

#include "mx/api/ApiCommon.h"

namespace mx
{
    namespace api
    {
        enum class LyricSyllable
        {
            unspecified, // a value was not provided
            single,
            begin,
            end,
            middle
        };
    
        class LyricData
        {
        public:
            LyricData() {}
            
            std::string text;
            LyricSyllable syllable;
            
        };
        
        MXAPI_EQUALS_BEGIN( LyricData )
        MXAPI_EQUALS_END;
        MXAPI_NOT_EQUALS_AND_VECTORS( LyricData );
    }
}
