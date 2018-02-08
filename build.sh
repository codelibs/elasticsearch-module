#!/bin/bash

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

VERSION=$1
if [ x"$VERSION" = "x" ] ; then
  echo "No version."
  exit 1
fi

BUILD_MODE=$2
if [ x"$BUILD_MODE" = "x" ] ; then
  BUILD_MODE=local
fi

ES_DIR=elasticsearch-${VERSION}
ES_BINARY_URL=https://artifacts.elastic.co/downloads/elasticsearch/${ES_DIR}.zip
ES_SOURCE_URL=https://github.com/elastic/elasticsearch/archive/v${VERSION}.zip
BUILD_DIR=target

mkdir -p $BUILD_DIR
cd $BUILD_DIR
rm -rf $ES_DIR

# Download source zip
if [ ! -f v${VERSION}.zip ] ; then
  wget $ES_SOURCE_URL
fi
if [ ! -f v${VERSION}.zip ] ; then
  echo "Failed to download v${VERSION}.zip."
  exit 1
fi
unzip -n v${VERSION}.zip > /dev/null

# Download binary zip
if [ ! -f ${ES_DIR}.zip ] ; then
  wget $ES_BINARY_URL
fi
if [ ! -f ${ES_DIR}.zip ] ; then
  echo "Failed to download ${ES_DIR}.zip."
  exit 1
fi
unzip -n ${ES_DIR}.zip > /dev/null

function generate_pom() {
  MODULE_DIR=$1
  MODULE_NAME=$2
  MODULE_TYPE=$3

  pushd  ${ES_DIR}/$MODULE_TYPE/${MODULE_DIR} > /dev/null
  MODULE_VERSION=`/bin/ls ${MODULE_NAME}*.jar | sed -e "s/^${MODULE_NAME}-\(.*\).jar/\1/"`
  POM_FILE=${MODULE_NAME}-${MODULE_VERSION}.pom
  GROUP_ID="org.codelibs.elasticsearch."`echo $MODULE_TYPE | sed -e "s/s$//"`

  echo "Generating $POM_FILE"
  echo '<?xml version="1.0" encoding="UTF-8"?>' > $POM_FILE
  echo '<project xmlns="http://maven.apache.org/POM/4.0.0" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' >> $POM_FILE
  echo '  <modelVersion>4.0.0</modelVersion>' >> $POM_FILE
  echo '  <groupId>'$GROUP_ID'</groupId>' >> $POM_FILE
  echo '  <artifactId>'$MODULE_NAME'</artifactId>' >> $POM_FILE
  echo '  <version>'$MODULE_VERSION'</version>' >> $POM_FILE
  echo '  <dependencies>' >> $POM_FILE

  for JAR_FILE in `/bin/ls *.jar | grep -v ^$MODULE_NAME` ; do
    JAR_NAME=`echo $JAR_FILE | sed -e "s/\(.*\)-[0-9].[0-9].*.jar/\1/g"`
    JAR_VERSION=`echo $JAR_FILE | sed -e "s/.*-\([0-9].[0-9].*\).jar/\1/g"`
    CLASSIFIER=`grep :$JAR_NAME:.*: build.gradle | sed -e "s/.*compile *['\"].*:$JAR_NAME:.*:\(.*\)['\"]/\1/"`
    if [ x"$CLASSIFIER" != "x" ] ; then
      JAR_VERSION=`echo $JAR_VERSION | sed -e "s/\-$CLASSIFIER$//"`
    fi
    GROUP_ID=`grep :$JAR_NAME: build.gradle | sed -e "s/.*compile *['\"]\(.*\):$JAR_NAME:.*/\1/"`
    if [ x"$JAR_NAME" = "xelasticsearch-scripting-painless-spi" ] ; then
      GROUP_ID="org.codelibs.elasticsearch.module"
      JAR_NAME="scripting-painless-spi"
    elif [ x"$GROUP_ID" = "x" ] ; then
      POMXML_FILE=`jar tf $JAR_FILE | grep pom.xml`
      jar xf $JAR_FILE $POMXML_FILE
      GROUP_ID=`cat $POMXML_FILE | xmllint --format - | sed -e "s/<project [^>]*>/<project>/" | xmllint --xpath "/project/groupId/text()" -`
      if [ x"$GROUP_ID" = "x" ] ; then
        GROUP_ID=`cat $POMXML_FILE | xmllint --format - | sed -e "s/<project [^>]*>/<project>/" | xmllint --xpath "/project/parent/groupId/text()" -`
      fi
    fi
    if [ x"$GROUP_ID" = "x" -o x"$JAR_VERSION" = "x" ] ; then
      echo "[$JAR_NAME] groupId or version is empty."
      exit 1
    fi
    echo '    <dependency>' >> $POM_FILE
    echo '      <groupId>'$GROUP_ID'</groupId>' >> $POM_FILE
    echo '      <artifactId>'$JAR_NAME'</artifactId>' >> $POM_FILE
    echo '      <version>'$JAR_VERSION'</version>' >> $POM_FILE
    if [ x"$CLASSIFIER" != "x" ] ; then
      echo '      <classifier>'$CLASSIFIER'</classifier>' >> $POM_FILE
    fi
    echo '    </dependency>' >> $POM_FILE
  done

  echo '  </dependencies>' >> $POM_FILE
  echo '  <inceptionYear>2009</inceptionYear>' >> $POM_FILE
  echo '  <licenses>' >> $POM_FILE
  echo '    <license>' >> $POM_FILE
  echo '      <name>The Apache Software License, Version 2.0</name>' >> $POM_FILE
  echo '      <url>http://www.apache.org/licenses/LICENSE-2.0.txt</url>' >> $POM_FILE
  echo '      <distribution>repo</distribution>' >> $POM_FILE
  echo '    </license>' >> $POM_FILE
  echo '  </licenses>' >> $POM_FILE
  echo '  <developers>' >> $POM_FILE
  echo '    <developer>' >> $POM_FILE
  echo '      <name>Elastic</name>' >> $POM_FILE
  echo '      <url>http://www.elastic.co</url>' >> $POM_FILE
  echo '    </developer>' >> $POM_FILE
  echo '    <developer>' >> $POM_FILE
  echo '      <name>CodeLibs</name>' >> $POM_FILE
  echo '      <url>http://www.codelibs.org/</url>' >> $POM_FILE
  echo '    </developer>' >> $POM_FILE
  echo '  </developers>' >> $POM_FILE
  echo '  <name>'$MODULE_NAME'</name>' >> $POM_FILE
  echo '  <description>Elasticsearch module: '$MODULE_NAME'</description>' >> $POM_FILE
  echo '  <url>https://github.com/codelibs/elasticsearch-module</url>' >> $POM_FILE
  echo '  <scm>' >> $POM_FILE
  echo '    <url>git@github.com:codelibs/elasticsearch-module.git</url>' >> $POM_FILE
  echo '  </scm>' >> $POM_FILE
  echo '</project>' >> $POM_FILE
  popd > /dev/null
}

function generate_source() {
  MODULE_DIR=$1
  MODULE_NAME=$2
  MODULE_TYPE=$3

  pushd  ${ES_DIR}/$MODULE_TYPE/${MODULE_DIR}/src/main/java > /dev/null
  SOURCE_FILE=${MODULE_NAME}-${MODULE_VERSION}-sources.jar

  echo "Generating $SOURCE_FILE"
  jar cvf ../../../$SOURCE_FILE * > /dev/null

  popd > /dev/null
}

function generate_javadoc() {
  MODULE_DIR=$1
  MODULE_NAME=$2
  MODULE_TYPE=$3

  pushd  ${ES_DIR}/$MODULE_TYPE/${MODULE_DIR} > /dev/null
  JAVADOC_FILE=${MODULE_NAME}-${MODULE_VERSION}-javadoc.jar

  echo "Generating $JAVADOC_FILE"
  mkdir -p src/main/javadoc
  javadoc -locale en -d src/main/javadoc -sourcepath src/main/java -subpackages org
  jar cvf $JAVADOC_FILE -C src/main/javadoc/ . > /dev/null

  popd > /dev/null
}

function deploy_files() {
  MODULE_DIR=$1
  MODULE_NAME=$2
  MODULE_TYPE=$3

  pushd  ${ES_DIR}/$MODULE_TYPE/${MODULE_DIR} > /dev/null
  POM_FILE=${MODULE_NAME}-${MODULE_VERSION}.pom
  BINARY_FILE=${MODULE_NAME}-${MODULE_VERSION}.jar
  SOURCE_FILE=${MODULE_NAME}-${MODULE_VERSION}-sources.jar
  JAVADOC_FILE=${MODULE_NAME}-${MODULE_VERSION}-javadoc.jar

  if [ x"$BUILD_MODE" = "xlocal" ] ; then
    echo "Deploying $POM_FILE to a local repository"
    mvn install:install-file -Dfile=$BINARY_FILE -DpomFile=$POM_FILE
    mvn install:install-file -Dfile=$SOURCE_FILE -DpomFile=$POM_FILE -Dclassifier=sources
    mvn install:install-file -Dfile=$JAVADOC_FILE -DpomFile=$POM_FILE -Dclassifier=javadoc
  elif [ x"$BUILD_MODE" = "xremote" ] ; then
    echo "Deploying $POM_FILE to a local repository"
    mvn gpg:sign-and-deploy-file -Durl=https://oss.sonatype.org/service/local/staging/deploy/maven2/ -DrepositoryId=sonatype-nexus-staging -DpomFile=$POM_FILE -Dfile=$BINARY_FILE
    mvn gpg:sign-and-deploy-file -Durl=https://oss.sonatype.org/service/local/staging/deploy/maven2/ -DrepositoryId=sonatype-nexus-staging -DpomFile=$POM_FILE -Dfile=$SOURCE_FILE -Dclassifier=sources
    mvn gpg:sign-and-deploy-file -Durl=https://oss.sonatype.org/service/local/staging/deploy/maven2/ -DrepositoryId=sonatype-nexus-staging -DpomFile=$POM_FILE -Dfile=$JAVADOC_FILE -Dclassifier=javadoc
  fi

  popd > /dev/null
}

function deplopy_lang_paiinless_spi() {
  MODULE_DIR=lang-painless/spi
  MODULE_NAME=scripting-painless-spi
  MODULE_TYPE=modules
  JAR_FILE=`/bin/ls $ES_DIR/$MODULE_TYPE/lang-painless/elasticsearch-scripting-painless-spi-*.jar`
  if [ ! -f $JAR_FILE ] ; then
    return
  fi
  NEW_JAR_FILE=`echo $JAR_FILE | sed -e "s/elasticsearch-scripting-painless-spi/spi\/scripting-painless-spi/"`
  ES_JAR_FILE=`echo $JAR_FILE | sed -e "s/elasticsearch-scripting-painless-spi/spi\/elasticsearch/"`
  cp $JAR_FILE $NEW_JAR_FILE
  touch $ES_JAR_FILE
  generate_pom $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  generate_source $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  generate_javadoc $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  deploy_files $MODULE_DIR $MODULE_NAME $MODULE_TYPE
}

function deplopy_plugin_classloader() {
  MODULE_DIR=plugin-classloader
  MODULE_NAME=plugin-classloader
  MODULE_TYPE=libs
  JAR_FILE=`/bin/ls $ES_DIR/lib/plugin-classloader-*.jar`
  if [ ! -f $JAR_FILE ] ; then
    return
  fi
  cp $JAR_FILE $ES_DIR/$MODULE_TYPE/plugin-classloader
  generate_pom $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  generate_source $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  generate_javadoc $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  deploy_files $MODULE_DIR $MODULE_NAME $MODULE_TYPE
}

deplopy_lang_paiinless_spi
deplopy_plugin_classloader

for MODULE_NAME in `/bin/ls -d ${ES_DIR}/modules/*/ | sed -e "s/.*\/\([^\/]*\)\//\1/"` ; do
  generate_pom $MODULE_NAME $MODULE_NAME modules
  generate_source $MODULE_NAME $MODULE_NAME modules
  generate_javadoc $MODULE_NAME $MODULE_NAME modules
  deploy_files $MODULE_NAME $MODULE_NAME modules
done

echo "Modules:"
grep ^classname ${ES_DIR}/modules/*/plugin-descriptor.properties | sed -e "s/.*classname=\(.*\)/\"\1\",/"


