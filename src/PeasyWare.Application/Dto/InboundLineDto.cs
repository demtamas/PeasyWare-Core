using System;
using System.Collections.Generic;
using System.Text;

namespace PeasyWare.Application.Dto
{
    public sealed class InboundLineDto
    {
        public int InboundLineId { get; init; }
        public int LineNo { get; init; }
        public string SkuCode { get; init; } = "";
        public string Description { get; init; } = "";
        public int ExpectedQty { get; init; }
        public int ReceivedQty { get; init; }
        public int OutstandingQty { get; init; }
    }

}
