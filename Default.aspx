<%@ Import Namespace="System" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Web" %>
<%@ Import Namespace="System.Xml" %>
<%@ Import Namespace="System.Reflection" %>
<%@ Page Language="c#" debug="true" %>
<script runat="server">

private string getHostname()
{
  return System.IO.File.ReadAllText(Server.MapPath(".")+@"\hostname.txt").ToLowerInvariant().Trim();
}

private string getClickOnceUrl()
{
  return System.IO.File.ReadAllText(@"c:\demo\extensions\navserver\clickonce.txt");
}

private string getProduct()
{
  return System.IO.File.ReadAllText(Server.MapPath(".")+@"\title.txt");
}

private string createQrImg(string link, string title, int width = 100, int height = 100)
{
  var encodedlink = System.Net.WebUtility.UrlEncode(link);
  return string.Format("<img src=\"https://chart.googleapis.com/chart?cht=qr&chs=100x100&chl={0}&chld=L|0\" title=\"{1}\" width=\"{2}\" height=\"{3}\" />", encodedlink, title, width, height);
}

private string getLandingPageUrl()
{
  return getHostname();
}

private string createQrForLandingPage()
{
  return createQrImg("http://"+getLandingPageUrl(), getProduct());
}

private string getCountry()
{
  if (System.IO.File.Exists(@"c:\demo\extensions\navserver\country.txt"))
  {
    var ct = System.IO.File.ReadAllText(@"c:\demo\extensions\navserver\country.txt").ToUpperInvariant().Trim();
    if (string.IsNullOrEmpty(ct)) {
      return "W1";
    }
    if (ct.StartsWith("FIN")) {
      return ct.Substring(3);
    }
    return ct;
  }
  return "W1";
}

private string getBuildNumber()
{
  if (System.IO.File.Exists(@"c:\demo\extensions\navserver\version.txt"))
  {
    var version = System.IO.File.ReadAllText(@"c:\demo\extensions\navserver\version.txt").Trim();
    var idx = version.IndexOf("-");
    if (idx < 0) { return version; }
    return version.Substring(0, idx);
  }
  return "";
}

private XmlDocument customSettings = null;

private bool GetCustomSettings()
{
  if ((this.customSettings == null) && (System.IO.File.Exists(@"c:\demo\extensions\navserver\CustomSettings.config")))
  {
    customSettings = new XmlDocument();
    customSettings.Load(@"c:\demo\extensions\navserver\CustomSettings.config");
  }
  return this.customSettings != null;
}

private string getWebBaseUrl()
{
  if (GetCustomSettings())
  {
    return customSettings.SelectSingleNode("//appSettings/add[@key='PublicWebBaseUrl']").Attributes["value"].Value.ToLowerInvariant();
  }
  return "";
}

private string getODataBaseUrl()
{
  if (GetCustomSettings())
  {
    return customSettings.SelectSingleNode("//appSettings/add[@key='PublicODataBaseUrl']").Attributes["value"].Value.ToLowerInvariant();
  }
  return "";
}

private string getSoapBaseUrl()
{
  if (GetCustomSettings())
  {
    return customSettings.SelectSingleNode("//appSettings/add[@key='PublicSOAPBaseUrl']").Attributes["value"].Value.ToLowerInvariant();
  }
  return "";
}

private bool isHttps()
{
  return getWebBaseUrl().StartsWith("https://");
}

private string getCompanyName()
{
  if (GetCustomSettings())
  {
    return customSettings.SelectSingleNode("//appSettings/add[@key='ServicesDefaultCompany']").Attributes["value"].Value;
  }
  return "";
}

private string getServerInstance()
{
  if (GetCustomSettings())
  {
    return customSettings.SelectSingleNode("//appSettings/add[@key='ServerInstance']").Attributes["value"].Value;
  }
  return "";
}

private string getAzureSQL()
{
  if (GetCustomSettings())
  {
    var DatabaseServer = customSettings.SelectSingleNode("//appSettings/add[@key='DatabaseServer']").Attributes["value"].Value;
    var DatabaseInstance = customSettings.SelectSingleNode("//appSettings/add[@key='DatabaseInstance']").Attributes["value"].Value;
    var DatabaseName = customSettings.SelectSingleNode("//appSettings/add[@key='DatabaseName']").Attributes["value"].Value;
    var len = DatabaseServer.IndexOf(".database.windows.net", StringComparison.OrdinalIgnoreCase);
    if (len>=0)
      return "Azure SQL<br />"+DatabaseServer+"<br />"+DatabaseName;
    if (!string.IsNullOrEmpty(DatabaseInstance))
      DatabaseInstance = "/"+DatabaseInstance;
    return "SQL Server<br />"+DatabaseServer+DatabaseInstance+"<br />"+DatabaseName;
  }
  return "";
}

</script>

<html>
<head>
    <title><%=getProduct() %></title>
    <style type="text/css">
        h1 {
            font-size: 2em;
            font-weight: 400;
            color: #000;
            margin: 0px;
        }

        h2 {
            font-size: 1.2em;
            margin-top: 2em;
        }

        .h2sub {
            font-weight: 100;
        }

        h3 {
            font-size: 1.2em;
            margin: 0px;
            line-height: 32pt;
        }

        h4 {
            font-size: 1em;
            margin: 0px;
            line-height: 24pt;
        }

        h6 {
            font-size: 10pt;
            position: relative;
            left: 10px;
            top: 120px;
            margin: 0px;
        }

        h5 {
            font-size: 10pt;
        }

        body {
            font-family: "Segoe UI","Lucida Grande",Verdana,Arial,Helvetica,sans-serif;
            font-size: 12px;
            color: #5f5f5f;
            margin-left: 20px;
        }

        table {
            table-layout: fixed;
            width: 100%;
        }

        td {
            vertical-align: top;
        }

        a {
            text-decoration: none;
            text-underline:none
        }
        #tenants {
            border-collapse:collapse;
        }

        #tenants td {
            text-align: center;
            border: 1px solid #808080;
            vertical-align: middle;
            margin: 2px 2px 2px 2px;
        }

	#tenants tr.alt td {
            background-color: #e0e0e0;
        }

	#tenants tr.head td {
            background-color: #c0c0c0;
        }

        #tenants td.tenant {
            text-align: left;
        }
    </style>
<script language="javascript"> 
function show(selected) {
  document.getElementById("texttd").style.backgroundColor = "#cccccc"; 
  for(i=1; i<=5; i++) {
    var textele = document.getElementById("text"+i);
    var linkele = document.getElementById("link"+i);
    var tdele = document.getElementById("td"+i);
    if (i == selected) {
      textele.style.display = "block";
      tdele.style.backgroundColor = "#cccccc";
    } else {
      textele.style.display = "none";
      tdele.style.backgroundColor = "#ffffff";
    }
  }
}

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
<body onload="JavaScript:timeRefresh(30000);">
  <table>
    <colgroup>
       <col span="1" style="width: 14%;">
       <col span="1" style="width: 70%;">
       <col span="1" style="width:  1%;">
       <col span="1" style="width: 15%;">
    </colgroup>
    <tr><td colspan="2">
    <table>
    <tr>
    <td rowspan="2" width="110"><% =createQrForLandingPage() %></td>
    <td style="vertical-align:bottom">&nbsp;<img src="Microsoft.png" width="108" height="23"></td>
    </tr><tr>
    <td style="vertical-align:top"><h1><%=getProduct() %></h1><%=getBuildNumber() %></td>
    </tr>
    </table>
    </td>
    <td></td>
    <td style="vertical-align:middle; color:#c0c0c0; white-space: nowrap"><p><%=getAzureSQL() %></p></td>
    </tr>
    <tr><td colspan="4"><img src="line.png" width="100%" height="14"></td></tr>
<%
  if (File.Exists(@"c:\demo\extensions\navserver\Certificate.cer")) {
%>
    <tr><td colspan="4"><h3>Download Self Signed Certificate</h3></td></tr>
    <tr>
      <td colspan="2">The <%=getProduct() %> is secured with a self-signed certificate. In order to connect to the environment, you must trust this certificate. Select operating system and browser to view the process for downloading and trusting the certificate:</td>
      <td></td>
      <td rowspan="2" style="white-space: nowrap"><a href="http://<%=getLandingPageUrl() %>:8080/Certificate.cer" target="_blank">Download Certificate</a></td>
    </tr>
    <tr>
      <td colspan="2">
<table border="0" cellspacing="0" cellpadding="5"><tr>
<td style="width: 225px; white-space: nowrap" id="td1" style="background-color: #ffffff"><a id="link1" href="javascript:show(1);">Windows&nbsp;(Edge/IE/Chrome)</a></td>
<td style="width: 225px; white-space: nowrap" id="td2" style="background-color: #ffffff"><a id="link2" href="javascript:show(2);">Windows&nbsp;(Firefox)</a></td>
<td style="width: 225px; white-space: nowrap" id="td3" style="background-color: #ffffff"><a id="link3" href="javascript:show(3);">Windows&nbsp;Phone</a></td>
<td style="width: 225px; white-space: nowrap" id="td4" style="background-color: #ffffff"><a id="link4" href="javascript:show(4);">iOS&nbsp;(Safari)</a></td>
<td style="width: 225px; white-space: nowrap" id="td5" style="background-color: #ffffff"><a id="link5" href="javascript:show(5);">Android</a></td>
</tr>
<tr>
  <td colspan="5" id="texttd" style="background-color: #ffffff">
<div id="text1" style="display: none"><p>Download and open the certificate file. Click <i>Install Certificate</i>, choose <i>Local Machine</i>, and then place the certificate in the <i>Trusted Root Certification Authorities</i> category.</p></div>
<div id="text2" style="display: none"><p>Open Options, Advanced, View Certificates, Servers and then choose <i>Add Exception</i>. Enter <i>https://<% =getHostname() %>/NAV</i>, choose <i>Get Certificate</i>, and then choose <i>Confirm Security Exception</i>.</p></div>
<div id="text3" style="display: none"><p>Choose the <i>download certificate</i> link. Install the certificate by following the certificate installation process.</p></div>
<div id="text4" style="display: none"><p>Choose the <i>download certificate</i> link. Install the certificate by following the certificate installation process.</p></div>
<div id="text5" style="display: none"><p>Choose the <i>download certificate</i> link. Launch the downloaded certificate, and then choose OK to install the certificate.</p></div>
  </td>
</tr>
</table>
      </td>
      <td colspan="2"></td>
    </tr>
<%
  }
  var rdps = System.IO.Directory.GetFiles(Server.MapPath("."), "*.rdp");
  if (rdps.Length > 0) {
%>
    <tr><td colspan="4"><h3>Remote Desktop Access</h3></td></tr>
<%
    for(int i=0; i<rdps.Length; i++) {
%>
      <tr>
        <td colspan="2">
<%
      if (i == 0) {
        if (rdps.Length > 1) {
%>
The <%=getProduct() %> contains multiple servers. You can connect to the individual servers by following these links.
<%
        } else {
%>
You can connect to the server in the <%=getProduct() %> by following this link.
<%
        }
      }
%>
        </td>
        <td></td>
        <td style="white-space: nowrap"><a href="http://<%=getLandingPageUrl() %>/<% =System.IO.Path.GetFileName(rdps[i]) %>"><% =System.IO.Path.GetFileNameWithoutExtension(rdps[i]) %></a></td>
      </tr>
<%
    }
  }
  if (System.IO.File.Exists(@"c:\demo\status.txt")) {
    var status = System.IO.File.ReadAllText(@"c:\demo\status.txt");
    if (status.Contains("Desktop setup complete!")) {
%>
      <tr><td colspan="4"><h3>Installation complete</h3></td></tr>
<%
    } else {
%>
      <tr><td colspan="4"><h3>Installation NOT complete</h3></td></tr>
<%
    }
%>
      <tr>
        <td colspan="2">
You can view the installation status by following this link.
        </td>
        <td></td>
        <td style="white-space: nowrap"><a href="http://<%=getLandingPageUrl() %>/status.aspx">View Installation Status</a></td>
      </tr>
<%
  }
  if (System.IO.Directory.Exists(@"c:\demo\extensions\navserver")) {
%>
    <tr><td colspan="4"><h3>Access the <%=getProduct() %> using UserName/Password Authentication</h3></td></tr>
<%
    if (isHttps()) {
%>
    <tr>
      <td colspan="2">If you have installed the Microsoft Dynamics NAV Universal App on your phone, tablet or desktop computer and want to configure the app to connect to this <%=getProduct() %>, choose this link.</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="ms-dynamicsnav://<% =getHostname() %>/nav">Configure App</a></td>
    </tr>
<%
    }
%>
    <tr>
      <td colspan="2">Choose these links to access the <%=getProduct() %> using the Web Client.</td>
      <td></td>  
      <td><a href="<% =getWebBaseUrl() %>" target="_blank">Web&nbsp;Client</a></td>
    </tr>
<%
    if (Directory.Exists(Server.MapPath(".") + @"\clickonce.txt")) {
%>
    <tr>
      <td colspan="2">The <%=getProduct() %> supports running the Microsoft Dynamics NAV Windows client over the internet. Choose this link to install the Microsoft Dynamics NAV Windows client using ClickOnce.</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="<%=getClickOnceUrl() %>" target="_blank">Install Windows Client</a></td>
    </tr>
<%
    }
%>
    <tr><td colspan="4"><h3>Access the <%=getProduct() %> using Web Services</h3></td></tr>
    <tr>
      <td colspan="2">The <%=getProduct() %> exposes functionality as SOAP web services. Choose this link to view the web services.</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="<% =getSoapBaseUrl() %>/services" target="_blank">View SOAP Web Services</a></td>
    </tr>
    <tr>
      <td colspan="2">The <%=getProduct() %> exposes data as restful OData web services. Choose this link to view the web services</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="<% =getODataBaseUrl() %>" target="_blank">View OData Web Services</a></td>
    </tr>

<%
    var vsix = System.IO.Directory.GetFiles(@"c:\demo\extensions\navserver", "*.vsix");
    if (vsix.Length == 1) {
%>    
    <tr><td colspan="4"><h3>Access the <%=getProduct() %> using Visual Studio Code</h3></td></tr>
    <tr>
      <td colspan="2">Download the AL Language Customization for Visual Studio Code (.vsix)</td>
      <td></td>  
      <td style="white-space: nowrap"><a href="http://<%=getLandingPageUrl() %>:8080/<% =System.IO.Path.GetFileName(vsix[0]) %>"><% =System.IO.Path.GetFileNameWithoutExtension(vsix[0]) %></a></td>
    </tr>
    <tr><td colspan="4">launch.json settings:</td></tr>
    <tr><td colspan="4" style="font-family: Courier, Monaco, monospace">&nbsp;&nbsp;"server": "https://<%=getHostname() %>",<br>
      &nbsp;&nbsp;"serverInstance": "NAV",<br>
      &nbsp;&nbsp;"tenant": "",<br>
      &nbsp;&nbsp;"authentication": "UserPassword",</td></tr>
    <tr><td colspan="4">app.json settings:</td></tr>
    <tr><td colspan="4" style="font-family: Courier, Monaco, monospace">&nbsp;&nbsp;"locale": "<%=getCountry() %>",</td></tr>
<%
    }
  }
%>
    <tr><td colspan="4">&nbsp;</td></tr>

  </table>
</body>
</html>