#!/bin/bash

cd `dirname $0`
BASE_DIR=`pwd`

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

VERSION=$1
if [ x"$VERSION" = "x" ] ; then
  echo "No version."
  exit 1
fi

BUILD_DIR=$BASE_DIR/target
ES_DIR=$BUILD_DIR/elasticsearch-${VERSION}
ES_BINARY_FILE=elasticsearch-${VERSION}-windows-x86_64
ES_BINARY_URL=https://artifacts.elastic.co/downloads/elasticsearch/${ES_BINARY_FILE}.zip
ES_SOURCE_URL=https://github.com/elastic/elasticsearch/archive/v${VERSION}.zip
REPO_DIR=$BUILD_DIR/repository

mkdir -p $BUILD_DIR
rm -rf $ES_DIR $REPO_DIR
mkdir -p $ES_DIR $REPO_DIR

cd $BUILD_DIR

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
if [ ! -f ${ES_BINARY_FILE}.zip ] ; then
  wget $ES_BINARY_URL
fi
if [ ! -f ${ES_BINARY_FILE}.zip ] ; then
  echo "Failed to download ${ES_BINARY_FILE}.zip."
  exit 1
fi
unzip -n ${ES_BINARY_FILE}.zip > /dev/null

rm -r $ES_DIR/x-pack

function generate_pom() {
  MODULE_DIR=$1
  MODULE_NAME=$2
  MODULE_TYPE=$3

  pushd  ${ES_DIR}/$MODULE_TYPE/${MODULE_DIR} > /dev/null
  JAR_FILE=`/bin/ls ${MODULE_NAME}*.jar `
  mv $JAR_FILE `echo $JAR_FILE | sed -e "s/-client//"`
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
    echo "processing $JAR_FILE in "`pwd`
    #cat build.gradle | grep compile | grep project
    sed -i 's/project(.:server.)/"org.elasticsearch:elasticsearch:${version}"/g' build.gradle
    sed -i 's/project(.:client:rest.)/"org.elasticsearch.client:elasticsearch-rest-client:${version}"/g' build.gradle
    sed -i 's/project(.:libs:elasticsearch-ssl-config.)/"org.elasticsearch:elasticsearch-ssl-config:${version}"/g' build.gradle
    JAR_NAME=`echo $JAR_FILE | sed -e "s/\(.*\)-[0-9].[0-9].*.jar/\1/g"`
    JAR_VERSION=`echo $JAR_FILE | sed -e "s/.*-\([0-9].[0-9].*\).jar/\1/g"`
    CLASSIFIER=`grep :$JAR_NAME:.*: build.gradle | sed -e "s/.*\(compile\|api\|implementation\).*['\"].*:$JAR_NAME:.*:\(.*\)['\"]/\2/"`
    if [ x"$CLASSIFIER" != "x" ] ; then
      JAR_VERSION=`echo $JAR_VERSION | sed -e "s/\-$CLASSIFIER$//"`
    fi
    GROUP_ID=`grep :$JAR_NAME: build.gradle | sed -e "s/.*\(compile\|api\|implementation\).*['\"]\(.*\):$JAR_NAME:.*/\2/"`
    if [ x"$JAR_NAME" = "xelasticsearch-scripting-painless-spi" ] ; then
      GROUP_ID="org.codelibs.elasticsearch.module"
      JAR_NAME="scripting-painless-spi"
    elif [ x"$JAR_NAME" = "xelasticsearch-grok" ] ; then
      GROUP_ID="org.codelibs.elasticsearch.lib"
      JAR_NAME="grok"
    elif [ x"$JAR_NAME" = "xelasticsearch-ssl-config" ] ; then
      GROUP_ID="org.codelibs.elasticsearch.lib"
      JAR_NAME="ssl-config"
    elif [ x"$JAR_NAME" = "xelasticsearch-dissect" ] ; then
      GROUP_ID="org.codelibs.elasticsearch.lib"
      JAR_NAME="dissect"
    elif [ x"$JAR_NAME" = "xelasticsearch-rest-client" ] ; then
      GROUP_ID="org.elasticsearch.client"
      JAR_NAME="elasticsearch-rest-client"
    elif [ x"$JAR_NAME" = "xreindex-client" ] ; then
      GROUP_ID="org.elasticsearch.plugin"
      JAR_NAME="reindex-client"
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

  if [[ "$MODULE_NAME" = "lang-painless" ]] ; then
    echo '    <dependency>' >> $POM_FILE
    echo '      <groupId>org.codelibs.elasticsearch.module</groupId>' >> $POM_FILE
    echo '      <artifactId>scripting-painless-spi</artifactId>' >> $POM_FILE
    echo '      <version>'$MODULE_VERSION'</version>' >> $POM_FILE
    echo '    </dependency>' >> $POM_FILE
  fi

  echo '  </dependencies>' >> $POM_FILE
  echo '  <inceptionYear>2009</inceptionYear>' >> $POM_FILE
  echo '  <licenses>' >> $POM_FILE
  echo '    <license>' >> $POM_FILE
  echo '      <name>Server Side Public License (SSPL) version 1</name>' >> $POM_FILE
  echo '      <url>https://www.mongodb.com/licensing/server-side-public-license</url>' >> $POM_FILE
  echo '      <distribution>repo</distribution>' >> $POM_FILE
  echo '    </license>' >> $POM_FILE
  echo '  </licenses>' >> $POM_FILE
  echo '  <developers>' >> $POM_FILE
  echo '    <developer>' >> $POM_FILE
  echo '      <name>Elastic</name>' >> $POM_FILE
  echo '      <url>https://www.elastic.co</url>' >> $POM_FILE
  echo '    </developer>' >> $POM_FILE
  echo '    <developer>' >> $POM_FILE
  echo '      <name>CodeLibs</name>' >> $POM_FILE
  echo '      <url>https://www.codelibs.org/</url>' >> $POM_FILE
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

  echo "Deploying $POM_FILE to a local repository"
  mvn install:install-file -Dfile=$BINARY_FILE -DpomFile=$POM_FILE
  mvn install:install-file -Dfile=$SOURCE_FILE -DpomFile=$POM_FILE -Dclassifier=sources
  mvn install:install-file -Dfile=$JAVADOC_FILE -DpomFile=$POM_FILE -Dclassifier=javadoc
  echo "Deploying $POM_FILE to a local repository"
  mvn deploy:deploy-file -Dgpg.skip=false -Durl=file:$REPO_DIR -Dfile=$BINARY_FILE -DpomFile=$POM_FILE
  mvn deploy:deploy-file -Dgpg.skip=false -Durl=file:$REPO_DIR -Dfile=$SOURCE_FILE -DpomFile=$POM_FILE -Dclassifier=sources
  mvn deploy:deploy-file -Dgpg.skip=false -Durl=file:$REPO_DIR -Dfile=$JAVADOC_FILE -DpomFile=$POM_FILE -Dclassifier=javadoc

  popd > /dev/null
}

function deplopy_lang_paiinless_spi() {
  MODULE_DIR=lang-painless/spi
  MODULE_NAME=scripting-painless-spi
  MODULE_TYPE=modules
  JAR_FILE=`/bin/ls $ES_DIR/$MODULE_TYPE/lang-painless/spi/elasticsearch-scripting-painless-spi-*.jar 2>/dev/null`
  if [ x"$JAR_FILE" = "x" ] ; then
    return
  fi
  NEW_JAR_FILE=`echo $JAR_FILE | sed -e "s/elasticsearch-scripting-painless-spi-/scripting-painless-spi-/"`
  cp $JAR_FILE $NEW_JAR_FILE
  generate_pom $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  generate_source $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  generate_javadoc $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  deploy_files $MODULE_DIR $MODULE_NAME $MODULE_TYPE
}

function deplopy_plugin_classloader() {
  MODULE_DIR=plugin-classloader
  MODULE_NAME=plugin-classloader
  MODULE_TYPE=libs
  JAR_FILE=`/bin/ls $ES_DIR/lib/*plugin-classloader-*.jar 2>/dev/null`
  if [ x"$JAR_FILE" = "x" ] ; then
    return
  fi
  cp $JAR_FILE $ES_DIR/$MODULE_TYPE/$MODULE_NAME/`basename $JAR_FILE|sed -e "s/elasticsearch-plugin-classloader-/plugin-classloader-/"`
  generate_pom $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  generate_source $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  generate_javadoc $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  deploy_files $MODULE_DIR $MODULE_NAME $MODULE_TYPE
}

function deplopy_grok() {
  MODULE_DIR=grok
  MODULE_NAME=grok
  MODULE_TYPE=libs
  JAR_FILE=`/bin/ls $ES_DIR/modules/ingest-common/elasticsearch-grok-*.jar 2>/dev/null`
  if [ x"$JAR_FILE" = "x" ] ; then
    return
  fi
  cp $JAR_FILE $ES_DIR/$MODULE_TYPE/$MODULE_NAME/`basename $JAR_FILE|sed -e "s/elasticsearch-grok-/grok-/"`
  generate_pom $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  generate_source $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  generate_javadoc $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  deploy_files $MODULE_DIR $MODULE_NAME $MODULE_TYPE
}

function deplopy_ssl_config() {
  MODULE_DIR=ssl-config
  MODULE_NAME=ssl-config
  MODULE_TYPE=libs
  JAR_FILE=`/bin/ls $ES_DIR/modules/reindex/elasticsearch-ssl-config-*.jar 2>/dev/null`
  if [ x"$JAR_FILE" = "x" ] ; then
    return
  fi
  cp $JAR_FILE $ES_DIR/$MODULE_TYPE/$MODULE_NAME/`basename $JAR_FILE|sed -e "s/elasticsearch-ssl-config-/ssl-config-/"`
  generate_pom $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  generate_source $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  generate_javadoc $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  deploy_files $MODULE_DIR $MODULE_NAME $MODULE_TYPE
}

function deplopy_dissect() {
  MODULE_DIR=dissect
  MODULE_NAME=dissect
  MODULE_TYPE=libs
  JAR_FILE=`/bin/ls $ES_DIR/modules/ingest-common/elasticsearch-dissect-*.jar 2>/dev/null`
  if [ x"$JAR_FILE" = "x" ] ; then
    return
  fi
  cp $JAR_FILE $ES_DIR/$MODULE_TYPE/$MODULE_NAME/`basename $JAR_FILE|sed -e "s/elasticsearch-dissect-/dissect-/"`
  generate_pom $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  generate_source $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  generate_javadoc $MODULE_DIR $MODULE_NAME $MODULE_TYPE
  deploy_files $MODULE_DIR $MODULE_NAME $MODULE_TYPE
}

deplopy_lang_paiinless_spi
deplopy_plugin_classloader
deplopy_grok
deplopy_ssl_config
deplopy_dissect

MODULE_NAMES=`ls ${ES_DIR}/modules/*/build.gradle | sed -e "s,.*/\([^/]*\)/build.gradle,\1,"`
for MODULE_NAME in $MODULE_NAMES ; do
  /bin/ls ${ES_DIR}/modules/${MODULE_NAME}/*.jar >/dev/null 2>&1
  if [ $? != 0 ] ; then
    continue
  fi
  generate_pom $MODULE_NAME $MODULE_NAME modules
  generate_source $MODULE_NAME $MODULE_NAME modules
  generate_javadoc $MODULE_NAME $MODULE_NAME modules
  deploy_files $MODULE_NAME $MODULE_NAME modules
done

echo "Modules:"
pushd $REPO_DIR/org/codelibs/elasticsearch
find * -type f | grep pom$

