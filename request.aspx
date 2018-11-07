<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Diagnostics" %>
<%@ Page Language="c#" debug="true" %>
<%
Response.ContentType = "text/plain";
var queryParameters = HttpUtility.ParseQueryString(Request.Url.Query);
var id = queryParameters.Get("id");
var silent = queryParameters.Get("silent");
if (String.IsNullOrEmpty(id)) {
  var cmd = queryParameters.Get("cmd");
  if (System.IO.File.Exists(string.Format(@"c:\demo\request\{0}.ps1",cmd))) {
    using (EventLog eventLog = new EventLog("Application")) 
    {
      eventLog.Source = "Application";
      if (silent != null && silent.ToLower() == "yes") {
        eventLog.WriteEntry(Request.Url.Query, EventLogEntryType.Information, 57711, 1);
        Response.Write("Request queued " + cmd);
      } else {
        id = Guid.NewGuid().ToString();
        eventLog.WriteEntry(id + Request.Url.Query, EventLogEntryType.Information, 57711, 1);
        System.Threading.Thread.Sleep(1000);
        queryParameters.Remove("requesttoken");
        queryParameters.Add("id", id);
        Response.Redirect(Request.Url.AbsolutePath+"?"+queryParameters.ToString());
      }
    }
  } else {
    Response.Write("Unknown request: " + cmd);
  }
} else {
  var filename = string.Format(@"c:\demo\request\{0}.txt", id);
  var running = true;
  while (running) { 
    try {
      if (System.IO.File.Exists(filename)) {
        Response.Write(System.IO.File.ReadAllText(filename));
        running = false;
      }
    } catch {
    }
    System.Threading.Thread.Sleep(1000);
  }
}
%>