<xsl:stylesheet
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:exsl="http://exslt.org/common"
  
  xmlns:acis="http://acis.openlib.org"
  exclude-result-prefixes='exsl xml acis'
  version="1.0">
 
  <xsl:import href='../user/page.xsl'/>
  <xsl:variable name='current-screen-id'></xsl:variable>

  <xsl:variable name='research-suggestions-number-text'>
    <xsl:if test='$response-data/*[name()=$record-sid]/research-suggestions-exact and 
                  number($response-data/*[name()=$record-sid]/research-suggestions-exact/text()) &gt; 0'>
      <span class='notification-number'>
        <xsl:value-of select='$response-data/*[name()=$record-sid]/research-suggestions-exact'/>
      </span>
      <xsl:text>&#160;</xsl:text>
    </xsl:if>
  </xsl:variable>

  <xsl:variable name='citation-suggestions-number-text'>
    <xsl:if test='$response-data/*[name()=$record-sid]/citation-suggestions-new-total and 
                  number($response-data/*[name()=$record-sid]/citation-suggestions-new-total/text()) &gt; 0'>
      <span class='notification-number'>
        <xsl:value-of select='$response-data/*[name()=$record-sid]/citation-suggestions-new-total'/>
      </span>
      <xsl:text>&#160;</xsl:text>
    </xsl:if>
  </xsl:variable>


  <xsl:template name='user-person-profile-menu'>
    <xsl:call-template name='link-filter'>
      <xsl:with-param name='content'>
        <xsl:text>
        </xsl:text>
    
        <p class='menu'>
    <acis:hl screen='personal-menu'>
      <xsl:text>&#160;</xsl:text>
      <a ref='@menu' title='main menu'>
        <xsl:choose>
          <xsl:when test='$record-about-owner'>Profile:</xsl:when>
          <xsl:otherwise>
            <span class='name'><xsl:value-of select='$record-name'/></span>
            <xsl:text>'s profile:</xsl:text>
          </xsl:otherwise>
        </xsl:choose>
      </a>
      <xsl:text>&#160;</xsl:text>
    </acis:hl>

    <xsl:text> </xsl:text>
    <acis:hl screen='personal-name'>
      <xsl:text>&#160;</xsl:text>
      <a ref='@name' title='name details'>names</a>
      <xsl:text>&#160;</xsl:text>
    </acis:hl>
    
    <xsl:text> </xsl:text>
    <acis:hl screen='personal-contact'>
      <xsl:text>&#160;</xsl:text>
      <a ref='@contact' title='contact information'>contact</a>
      <xsl:text>&#160;</xsl:text>
    </acis:hl>
       
    <xsl:text> </xsl:text>
    <acis:hl screen='affiliations'>
      <xsl:text>&#160;</xsl:text>
      <a ref='@affiliations' title='places where you work'>affiliations</a>
      <xsl:text>&#160;</xsl:text>
    </acis:hl>
    
      <xsl:text> </xsl:text>

    <acis:hl screen='research/main'>
      <xsl:text>&#160;</xsl:text>
      <a ref='@research' title='research profile' >research</a>
      <xsl:text>&#160;</xsl:text>
      <xsl:copy-of select='$research-suggestions-number-text'/>
    </acis:hl>

    <!--[if-config(citations-profile)]
    <xsl:text> </xsl:text>
    <acis:hl screen='citations'>
      <xsl:text>&#160;</xsl:text>
      <a ref='@citations' title='citation profile' >citations</a>
      <xsl:text>&#160;</xsl:text>
      <xsl:copy-of select='$citation-suggestions-number-text'/>
    </acis:hl>
    [end-if]-->

    <xsl:text> | </xsl:text>
    <acis:hl screen='personal-overview'>
      <xsl:text>&#160;</xsl:text>
      <a ref='@profile-overview' title='current state of the profile' >overview</a>
      <xsl:text>&#160;</xsl:text>
    </acis:hl>
    </p>

<xsl:text> 
</xsl:text>

    </xsl:with-param></xsl:call-template>
  </xsl:template>

  
  <!--  USER'S PERSON RECORD MENU   -->
  <xsl:template name='user-person-menu'>  
    <ul class='menu'>
      <li><a ref='@name' >name details</a></li>
      <li><a ref='@contact' >contact details</a></li>
      <li><a ref='@affiliations' >affiliations</a></li>
      <li><a ref='@research' >research</a></li>
      <!--[if-config(citations-profile)]
      <li><a ref='@citations' >citations</a></li>
      [end-if]-->
    </ul>
  </xsl:template>

</xsl:stylesheet>