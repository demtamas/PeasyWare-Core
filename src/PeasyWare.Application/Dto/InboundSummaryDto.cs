using System;
using System.Collections.Generic;
using System.Text;

namespace PeasyWare.Application.Dto
{
    public class InboundSummaryDto
    {
        public bool   Exists           { get; set; }
        public bool   IsReceivable     { get; set; }
        public bool   HasExpectedUnits { get; set; }

        /// <summary>
        /// Inbound mode as stored on the delivery header.
        /// "SSCC" = pre-advised with expected handling units.
        /// "MANUAL" = line-based, no pre-advised SSCCs.
        /// NULL = not yet activated (mode not yet determined).
        /// </summary>
        public string? InboundMode { get; set; }
    }
}
