using System;
using System.Collections.Generic;
using System.Text;

namespace PeasyWare.Desktop.Infrastructure
{
    internal interface IToolbarAware
    {
        void ConfigureToolbar(ToolStrip toolStrip);
    }
}
