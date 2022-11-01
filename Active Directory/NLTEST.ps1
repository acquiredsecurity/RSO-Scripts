$scriptname = "NLTest" # set a variable we will use later as the "ServerHost" and "LogFile"
function runfunc(
    [Parameter(Mandatory=$true)]$token, #DataSet write token
    [Parameter()][string[]]$servermeta #servermeta argument to add custom DataSet server fields   
    ){    
    $logdataset = Get-DataSetLogger($token) # Get a new DataSet Logger
    $logdataset.SetServerHost($scriptname) # Set ServerHost
    $logdataset.SetGlobal_LogFile($scriptname) # Set LogFile name applied globally to all events from this script
    $logdataset.AddSessionAttribute("Endpoint", [Environment]::MachineName) # Add machine name as "Endpoint" session attribute
    $logdataset.AddSessionAttributes($servermeta)
    
    # Do your script actions here
    Import-Module ActiveDirectory
    $nltests = Get-WMIObject Win32_NTDomain | Select Description ,  DomainName , DomainControllerName , Status , ClientSiteName , DcSiteName , DNSForestName , DomainControllerAddress
    ForEach ($nltest in $nltests) {
        $logdataset.AddEvent(($nltest | Select Description , DomainName , DomainControllerName , Status , ClientSiteName , DcSiteName , DNSForestName , DomainControllerAddress | Get-ObjectDatesToString -DateFormat "yyyy-MM-dd HH:mm:ss"))      
    
        function Get-ObjectDatesToString(
        [Parameter(ValueFromPipeline, Mandatory = $true)]$object,
        [Parameter()][string]$DateFormat #https://docs.microsoft.com/en-us/dotnet/standard/base-types/custom-date-and-time-format-strings?view=netframework-4.8
    ) {
        if (!$DateFormat) {
            $DateFormat = "yyyy-MM-dd HH:mm:ss"
        }
    
        foreach ($obj_prop in $object.PsObject.Properties) {
            if (($obj_prop.Value) -and ($obj_prop.Value).GetType().Name -eq 'DateTime') {
				#Write-Host $localtime$
				#Write-Host $obj_prop
				#Write-Host $obj_prop.Value
				$UtcTime =  ($obj_prop.Value.ToUniversalTime() | Get-Date -Format $DateFormat).ToString()
				$EpochTime =  ($obj_prop.Value.ToUniversalTime() | Get-Date -UFormat %s).ToString()
				#Write-Host $UtcTime
				
				
                $object.PSObject.Properties.Remove($obj_prop.Name)
                $object | Add-Member -Force -MemberType NoteProperty -Name $obj_prop.Name -Value $UtcTime
				$object | Add-Member -Force -MemberType NoteProperty -Name "EpochTimeCreated" -Value $EpochTime
            }
        } 
        return $object
}
     
    
    } 
    
    $logdataset.FlushEvents()
    }

    if (Get-Module LogToDataSet) {Remove-Module LogToDataSet}
New-Module -Name 'LogToDataSet' -ScriptBlock {

    $dataset_region = "us";
    # $dataset_region = "eu"; # uncomment to use DataSet EU

    $logtodataset_source = @"     
    using System.Collections;
    using System.Collections.Generic;
    using System.IO;
    using System.Text;

    public class DataSetEvent {        
        public string ts;     // timestamp in nanoseconds as string
        public int sev; //// 0-6 - "finest, finer, fine, info, warning, error, fatal"
        public Hashtable attrs; // // event attributes

        public DataSetEvent() {                
            this.ts = (System.DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()*1000000).ToString();// // Get nanosecond time
            this.sev = 3;// // set default severity 3
            this.attrs = new Hashtable();
            this.attrs.Add("logfile", "");
            this.attrs.Add("parser", "json");
        }

        public void SetEventAttributes(Hashtable attributes) {
            this.attrs = attributes;
        }

        public void AddEventAttribute(string key, string value) {
            if (this.attrs.ContainsKey(key)) {
                this.attrs.Remove(key);
            }
            this.attrs.Add(key, value);
        }
    }

    public class DataSetLog {
        public string token;
        public string session;
        public Hashtable sessionInfo;
        public System.Collections.Generic.List<DataSetEvent> events;
        
        public DataSetLog()
        {
            this.session = System.Guid.NewGuid().ToString();
            this.sessionInfo = new Hashtable();
            this.sessionInfo.Add("serverHost", "");
            this.events = new System.Collections.Generic.List<DataSetEvent>();        
        }

        public DataSetLog(string token = null) 
        {
            this.token = token;
        }    

        public void SetToken(string token) {
            this.token = token;
        }
    }

    public class LogToDataSet {
        public string datasetus = "https://xdr.us1.sentinelone.net/api/addEvents";    
        public string dataseteu = "https://xdr.us1.sentinelone.net/api/addEvents";    
        public string dataseturl = "";
        public DataSetLog session;
        public string global_Event_Logfile; // logfile to apply to all events added
        public Hashtable global_Event_Attrs; // event attributes to apply to all events added    
        public System.Collections.Generic.Queue<DataSetEvent> EventQueue;  // event queue 
        public long lastTs ; // store last event timestamp, each event added must have a timestamp > previous
        public int MaxEvents; // max events in session before sending

        public LogToDataSet(string token, string url = "us", int MaxEvents = 1000) {
            this.session = new DataSetLog();
            this.lastTs = 0;        
            this.session.token = token;    
            this.MaxEvents = MaxEvents;    
            this.EventQueue = new System.Collections.Generic.Queue<DataSetEvent>(); 
            switch (url.ToLower()) {
                case "us":
                    this.dataseturl = this.datasetus;
                    break;
                case "eu":
                    this.dataseturl = this.dataseteu;      
                    break;      
                default:
                    this.dataseturl = url;
                    break;
            }        
        }   

        public void SetToken(string token) {
            this.session.SetToken(token);
        }

        public void SetSessionAttributes(Hashtable attributes) {
            this.session.sessionInfo = attributes;
        }
        
        public void AddSessionAttribute(string key, string value) {
            if (this.session.sessionInfo.ContainsKey(key)) {
                this.session.sessionInfo.Remove(key);
            }
            this.session.sessionInfo.Add(key, value);
        }

        public void SetServerHost(string serverHost) {
            this.AddSessionAttribute("serverHost", serverHost) ;       
        }

        public void AddSessionAttributes<T>(T attrs) {} //replace in powershell
        public void AddEventObject(DataSetEvent sevent) {} //replace in powershell
        public void AddEvent(object aevent) {} //replace in powershell
        public void FlushEvents() {} //replace in powershell
    }
"@
        
    Add-Type -TypeDefinition $logtodataset_source
    $log2dataset = New-Object LogToDataSet("", $dataset_region)

    Add-Member -InputObject $log2dataset -MemberType ScriptMethod -Name "AddEventObject" -Force -Value {
        param([DataSetEvent]$addevent)
        
        $eventts = [int64]$addevent.ts
        if ($eventts -le $this.lastTs) {
            $eventts +=1
            $addevent.ts = [string]$eventts            
            $this.lastTs = $eventts
        } else {
            $this.lastTs = $eventts
        }        
        if ($this.global_Event_Attrs.Count -ne 0) {
            foreach ($attr in $this.global_Event_Attrs.Keys) {
                $addevent.AddEventAttribute($attr, $this.global_Event_Attrs[$attr])
            }
        }
        if ($this.global_Event_Logfile -ne "") {
            $addevent.AddEventAttribute("logfile", $this.global_Event_Logfile)            
        }            
        
        $this.EventQueue.Enqueue($addevent)                    
        
        if ($this.EventQueue.Count -ge $this.MaxEvents) {
            $this.FlushEvents()
        }                
    }
    
    Add-Member -InputObject $log2dataset -MemberType ScriptMethod -Name "AddEvent" -Force -Value {
        param($message)
    
        $emessage = ""
        if ($message.GetType().Name -eq "string") {
            $emessage = $message
        }
        else {
            $emessage = ($message | ConvertTo-Json -Compress)
        }
        [DataSetEvent]$newevent = New-Object DataSetEvent
        $newevent.AddEventAttribute("message", $emessage)
        $this.AddEventObject($newevent)       
    }

    Add-Member -InputObject $log2dataset -MemberType ScriptMethod -Name "AddSessionAttributes" -Force -Value {
        param($attrs)

        if ($attrs) {
            if ($attrs.GetType().Name -eq 'String[]') {
                try {
                        $attrs = ConvertFrom-StringData -StringData ($attrs -join "`n") -ErrorVariable ConvErr
                }
                catch {Write-Host "Error Converting Session Attributes"}                      
                }     
                if ($attrs -and $attrs.GetType().Name -eq 'Hashtable') {
                    $attrs.GetEnumerator() | ForEach-Object {
                        $this.AddSessionAttribute($_.Key, $_.Value)
                }       
            }            
        }    
    }

    Add-Member -InputObject $log2dataset -MemberType ScriptMethod -Name "SetGlobal_LogFile" -Force -Value {
        param($logfile)

        $this.global_Event_Logfile = $logfile
    }

    Add-Member -InputObject $log2dataset -MemberType ScriptMethod -Name "SetGlobal_EventAttrs" -Force -Value {
        param($attrs)

        $this.global_Event_Attrs = $attrs
    }

    Add-Member -InputObject $log2dataset -MemberType ScriptMethod -Name "FlushEvents" -Force -Value {   
        while ($this.EventQueue.Count -ne 0) {
            for ($i = 0; $i -lt $this.MaxEvents; $i++) {
                if ($this.EventQueue.Count -ne 0) {
                    $this.session.events.Add($this.EventQueue.Dequeue())
                }                    
            }
            try{
                $body = ($this.session | ConvertTo-Json -Compress -Depth 100)      
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12          
                $response = Invoke-RestMethod -Uri $this.dataseturl -Method 'Post' -Body $body -ContentType 'application/json'
                if ($response.status -eq 'success') {                        
                    $this.session.events.Clear()    
                } else {
                    Write-Error "Error Sending To DataSet: Status: $($response.status) - Message: $($response.message)"            
                }  
            } 
            catch {
                Write-Error "Error Sending To DataSet - $($Error)"
            }
        }        
    } 

    
function Get-ObjectDatesToString(
    [Parameter(ValueFromPipeline, Mandatory=$true)]$object,
    [Parameter()][string]$DateFormat #https://docs.microsoft.com/en-us/dotnet/standard/base-types/custom-date-and-time-format-strings?view=netframework-4.8
) {
    if (!$DateFormat) {
    $DateFormat = ""
    }
    
    foreach($obj_prop in $object.PsObject.Properties) {
        if (($obj_prop.Value) -and ($obj_prop.Value).GetType().Name -eq 'DateTime') {
            $object.PSObject.Properties.Remove($obj_prop.Name)
            $object | Add-Member -Force -MemberType NoteProperty -Name $obj_prop.Name -Value ($obj_prop.Value | Get-Date -Format $DateFormat).ToString()
        }
    } 
    return $object
}
function Get-DataSetLogger($token) {        
    $log2dataset.SetToken($token)
    return $log2dataset # Initialize DataSet Logger
}
    
    Export-ModuleMember -Function Get-DataSetLogger  
    Export-ModuleMember -Function Get-ObjectDatesToString    
} | Import-Module
#Requires -Version 3.0


runfunc @Args # kick off the script func after importing module
