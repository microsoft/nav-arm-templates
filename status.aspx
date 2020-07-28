<%@ Import Namespace="System" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Web" %>
<%@ Import Namespace="System.Xml" %>
<%@ Import Namespace="System.Reflection" %>
<%@ Import Namespace="System.Diagnostics" %>
<%@ Page Language="c#" debug="true" %>
<script runat="server">
private string getHostname()
{
  return System.IO.File.ReadAllText(Server.MapPath(".")+@"\hostname.txt").ToLowerInvariant().Trim();
}
private string getLandingPageUrl()
{
  if (isTraefikUsed())
    return getHostname() + ":8180";
  else
    return getHostname();
}
private bool isTraefikUsed()
{
  return System.IO.File.Exists(@"c:\programdata\bccontainerhelper\traefikforbc\traefik.txt");
}
</script>
<%
if (Request.Url.AbsoluteUri.Contains("?timesinceupdate")) {
  Response.Write((int)(System.DateTime.Now - System.IO.File.GetLastWriteTime(@"c:\demo\status.txt")).TotalSeconds);
} else {
%>
<html>
<head>
    <title>Microsoft Dynamics NAV Installation Status</title>
    <style type="text/css">
        body {
            font-family: "Segoe UI","Lucida Grande",Verdana,Arial,Helvetica,sans-serif;
            font-size: 16px;
            color: #c0c0c0;
            background: #000000;
            margin-left: 20px;
        }

    </style>
<script type="text/JavaScript">
function timeRefresh(timeoutPeriod) 
{
  setTimeout("refresh();",timeoutPeriod);
}

function refresh() 
{
  if (window.location.href.indexOf('?norefresh') == -1)
  {
    location.reload(true);
  }
}
</script>
</head>
<body onload="JavaScript:timeRefresh(10000);">
<p>
<a href="http://<%=getLandingPageUrl() %>">View Landing Page</a>&nbsp;&nbsp;
<%
if (Request.Url.AbsoluteUri.Contains("norefresh")) {
%>
  <a href="http://<%=getLandingPageUrl() %>/status.aspx">Enable refresh</a>&nbsp;&nbsp;
<%
} else {
%>
  <a href="http://<%=getLandingPageUrl() %>/status.aspx?norefresh">Disable refresh</a>
<%
}
%>
</p><hr>
<%
  try
  {
    var lines = System.IO.File.ReadAllLines(@"c:\demo\status.txt");
    Array.Reverse(lines);
    foreach(var line in lines) {
%>
<%=line %><br>
<%
    }
  } catch(Exception) 
  {
%>
  <p>Error loading status, page should refresh in 10 seconds.</p>
<%
  }
%>
</body>
</html>
<%
}
%>