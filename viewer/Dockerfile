# Use a imagem base do Tomcat 8.5
FROM tomcat:8.5-jre8

RUN apt-get update && apt-get upgrade -y

# Enable and install SSH
# ssh root@127.0.0.1 -p 2222 -c aes256-cbc
ENV SSH_PASSWD "root:Docker!"
RUN apt-get install -y --no-install-recommends dialog \
    && apt-get update \
    && apt-get install -y --no-install-recommends openssh-server \
    && echo "$SSH_PASSWD" | chpasswd 

COPY sshd_config /etc/ssh/

COPY downloads/oauth2-proxy-v7.6.0.linux-amd64.tar.gz oauth2-proxy-v7.6.0.linux-amd64.tar.gz
RUN tar -xzf oauth2-proxy-v7.6.0.linux-amd64.tar.gz --strip-components=1 -C /opt/
RUN rm oauth2-proxy-v7.6.0.linux-amd64.tar.gz

# # Deps, oauth2-proxy, Protege
RUN apt-get install -y vim golang graphviz netcat

EXPOSE 80 8080 2222

# Essential Viewer and Essential Import Utility
COPY ./downloads/essential_import_utility_292.war /usr/local/tomcat/webapps/essential_import_utility.war

# Create a default redirect
RUN mkdir /usr/local/tomcat/webapps/ROOT
RUN echo '<% response.sendRedirect("/essential_viewer/"); %>' > /usr/local/tomcat/webapps/ROOT/index.jsp
# Change port of tocat
RUN sed -i 's/8080/9090/' /usr/local/tomcat/conf/server.xml
# Change maxHttpHeaderSize in case to use Oauth2 Proxy with Azure Entra ID
RUN sed -i 's/connectionTimeout="20000"/connectionTimeout="20000" maxHttpHeaderSize="24576"/' /usr/local/tomcat/conf/server.xml
# Copy tomcat-users 
COPY tomcat-users.xml /usr/local/tomcat/conf/tomcat-users.xml

COPY startup.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh

ENTRYPOINT ["/usr/local/bin/startup.sh"]
