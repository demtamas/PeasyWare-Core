using System;
using System.Collections.Generic;
using System.Text;

namespace PeasyWare.Application.Dto
{
    public class InboundSummaryDto
    {
        public bool Exists { get; set; }
        public bool IsReceivable { get; set; }
        public bool HasExpectedUnits { get; set; }
    }

}
