# Elasticsearch Module

This project provides an environment to build module jar files.

## Version

- Maven Central(-7.10): [https://repo1.maven.org/maven2/](https://repo1.maven.org/maven2/)
- CodeLibs Repository(7.11-): [https://maven.codelibs.org/](https://maven.codelibs.org/)

### For Maven User

You can add CodeLibs Repository as below:

```
<repositories>
    ...
	<repository>
		<id>codelibs.org</id>
		<name>CodeLibs Repository</name>
		<url>https://maven.codelibs.org/</url>
	</repository>
</repositories>
```

## Build

### Deploy Local Maven Repository

    $ ./build.sh <version>
