import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart';

const JAVA_LTS_VERSION = 21; // arm64 builds only available for openjdk21
// headless version not available for arm64
// https://docs.azul.com/core/zulu-openjdk/supported-platforms
const List<JavaBundleVersions> JAVA_BUNDLE_VERSIONS = [JavaBundleVersions.jre, JavaBundleVersions.jdk];
const OPERATING_SYSTEMS = [OperatingSystem.linux_musl_amd64, OperatingSystem.linux_arm64];
const DOCKER_TAG_API = "https://registry.hub.docker.com/v2/repositories/josxha/zulu-openjdk/tags?page=";

bool DRY_RUN = false;
bool FORCE_BUILDS = false;

main(List<String> args) async {
  for (var arg in args) {
    switch (arg) {
      case "force":
        FORCE_BUILDS = true;
        break;
      case "dry-run":
        DRY_RUN = true;
        break;
      default:
        throw "Unknown argument: '$arg'";
    }
  }

  var dockerImageTags = await getDockerImageTags();

  for (var javaBundleVersion in JAVA_BUNDLE_VERSIONS) {
    String? imageTag;
    Map<OperatingSystem, ZuluData> data = {};
    for (var os in OPERATING_SYSTEMS) {
      var zuluData = await getZuluData(
        features: javaBundleVersion.zuluString,
        os: os,
      );
      data[os] = zuluData;

      imageTag = "${javaBundleVersion.bundleType}-$JAVA_LTS_VERSION-${zuluData.zuluVersion}-${os.arch.docker}";
      print("[$imageTag] Check if the image is up to date...");
      if (dockerImageTags.contains(imageTag)) {
        // image already exists
        if (FORCE_BUILDS) {
          print("[$imageTag] Image exists but force update enabled.");
        } else {
          print("[$imageTag] Image exists, skip build.");
          continue;
        }
      }

      // image doesn't exist yet, build arch specific image
      print("[$imageTag] Build and push image");
      // download openJDK archives
      var response = await get(Uri.parse(zuluData.url));
      print("downloading file from ${zuluData.url}");
      if (response.statusCode != 200)
        throw "Couldn't download ${zuluData.name}\n${response.body}";
      await File("openjdk-${os.arch.docker}.tar.gz").writeAsBytes(response.bodyBytes);
      await dockerBuildAndPush(imageTag, os.arch);
      dockerImageTags.add(imageTag);
    }

    // build multi arch image
    for (var dockerImageTag in dockerImageTags) {
      var list = dockerImageTag.split("-");
      // check if it is a arch specific image
      if (list.length == 4 && list.last == OPERATING_SYSTEMS.first.arch.docker) {
        var multiArchImageTag = dockerImageTag.substring(0, dockerImageTag.lastIndexOf("-"));
        // check if a multi arch image already exists
        if (!dockerImageTags.contains(multiArchImageTag)) {
          // check if images of all other architectures exist
          var allArchExist = true;
          for (var os in OPERATING_SYSTEMS.sublist(1)) {
            if (!dockerImageTags.contains("$multiArchImageTag-${os.arch.docker}")) {
              allArchExist = false;
            }
          }
          if (allArchExist) {
            // build multi arch image
            var fromImageTags = OPERATING_SYSTEMS.map((os) => "$multiArchImageTag-${os.arch.docker}").toList();
            await dockerCreateAndPushManifest(multiArchImageTag, fromImageTags);
            await dockerCreateAndPushManifest("${javaBundleVersion.bundleType}-$JAVA_LTS_VERSION", fromImageTags);
            await dockerCreateAndPushManifest(javaBundleVersion.bundleType, fromImageTags);
            if (javaBundleVersion == JavaBundleVersions.jre) {
              await dockerCreateAndPushManifest("latest", fromImageTags);
            }
          }
        }
      }
    }
    print("[$imageTag] Built, pushed and cleaned up successfully!");
  }
}

Future<void> dockerCreateAndPushManifest(String imageTag, List<String> fromImageTags) async {
  //create manifest
  var args = [
    "manifest", "create",
    "josxha/zulu-openjdk:$imageTag",
  ];
  for (var fromImageTag in fromImageTags) {
    args.addAll(["--amend", "josxha/zulu-openjdk:$fromImageTag"]);
  }
  var result = await Process.run("docker", args);
  if (result.exitCode != 0) {
    print(result.stdout);
    print(result.stderr);
    throw "Couldn't create docker manifest.";
  }
  // push the manifest
  print('docker manifest push josxha/zulu-openjdk:$imageTag');
  result = await Process.run("docker", [
    "manifest", "push",
    "josxha/zulu-openjdk:$imageTag",
  ]);
  if (result.exitCode != 0) {
    print(result.stdout);
    print(result.stderr);
    throw "Couldn't push docker manifest.";
  }
}

/// Data object for the zulu api response
/// Azul API documentation:
/// https://app.swaggerhub.com/domains-docs/azul/zulu-download-api-shared/1.0#/components/pathitems/Bundles/get
Future<ZuluData> getZuluData({required String features, required OperatingSystem os, int java_version = JAVA_LTS_VERSION}) async {
  // Example url:
  // https://api.azul.com/zulu/download/community/v1.0/bundles/latest/?os=linux_musl&arch=arm&hw_bitness=64&bundle_type=jre&ext=&java_version=17&features=headfull
  var uri = Uri(
    scheme: "https",
    host: "api.azul.com",
    path: "zulu/download/community/v1.0/bundles/latest",
    queryParameters: {
      "os": os.name,
      "arch": os.arch.zulu,
      "hw_bitness": os.bitness.toString(),
      "java_version": java_version.toString(),
      "features": features,
      "ext": "tar.gz",
    },
  );
  print(uri);
  var response = await get(uri);
  switch (response.statusCode) {
    case 200:
      return ZuluData.parse(jsonDecode(response.body));
    case 404:
      throw "No Build available with that specification (404).\n$uri";
    default:
      throw "Error, received status code ${response.statusCode} from azul api.\n${response.body}";
  }
}

Future<void> dockerBuildAndPush(String imageTag, Architecture architecture) async {
  var args = [
    "buildx", "build", ".",
    "--push",
    "-f", "Dockerfile.${architecture.docker}",
    "--platform", architecture.dockerFull,
    "--tag", "josxha/zulu-openjdk:$imageTag",
  ];
  if (DRY_RUN)
    return;
  var taskResult = Process.runSync("docker", args);
  if (taskResult.exitCode != 0) {
    print(taskResult.stdout);
    print(taskResult.stderr);
    throw Exception("Couldn't run docker build for $imageTag.");
  }
}

Future<List<String>> getDockerImageTags() async {
  List<String> tags = [];
  int page = 1;
  while (true) {
    var uri = Uri.parse("$DOCKER_TAG_API$page");
    print(uri);
    var response = await get(uri);
    Map<String, dynamic> json = jsonDecode(response.body);
    List jsonList = json["results"];
    tags.addAll(jsonList.map((listElement) => listElement["name"] as String).toList());
    if (json['next'] == null)
      break;
    page++;
  }
  return tags;
}

class ZuluData {
  final int id;

  /// download url
  final String url;

  /// x86, arm
  final String arch;

  /// Filters the result by the type of floating point ABI this bundle uses.
  /// Only applies to 32-bit ARM builds.
  final String abi;

  /// 32, 64
  final String hw_bitness;

  /// v8
  final List<String> cpu_gen;

  /// linux, linux_musl (alpine), macos, windows, solaris, qnx
  final String os;

  /// .tar.gz
  final String extension;

  /// jre, jdk
  final String bundle_type;

  /// CPU (Critical Patch Update)
  /// PSU (Patch Set Update)
  final String release_type;

  /// ga - General Availability
  /// ea - Early Access
  /// both - General Availability and Early Access
  final String release_status;

  /// lts - Long Term Support
  /// mts - Medium Term Support
  /// sts - Short Term Support
  final String support_term;

  /// Whether only the latest bundle(s) matching the filter criteria
  /// should be returned
  final bool latest;

  /// file name
  final String name;

  /// timestamp
  final DateTime last_modified;

  /// Vendor specific distribution number. Filters the results by the version
  /// of Zulu, in a format of 4 numbers: major version, minor version, revision
  /// and patch − separated by dots (similar to semantic versioning). Numbers
  /// can be omitted; omitted number corresponds to all values.
  final List<int> zuluVersionArray;

  /// Filters the result by the Java version, in a format of 3+ numbers: major
  /// version, minor version (which is typically zero for most versions of
  /// the JDK), patch, revision, etc − separated by dots (similar to semantic
  /// versioning). Numbers can be omitted; omitted number corresponds to
  /// all values.
  final List<int> javaVersionArray;

  /// file size
  final int size;
  final String md5_hash;
  final String sha265_hash;
  final String bundle_uuid;

  /// bundles with support for JavaFX
  final bool javafx;

  /// cp3 - Compact Profile compact3
  /// fx - JavaFX API
  /// headful or headfull - Headful JVM
  /// headless - Headless JVM
  /// jdk - JDK rather than JRE
  final List<String> features;

  ZuluData({
    required this.url,
    required this.extension,
    required this.last_modified,
    required this.name,
    required this.javaVersionArray,
    required this.sha265_hash,
    required this.zuluVersionArray,
    required this.arch,
    required this.hw_bitness,
    required this.bundle_type,
    required this.abi,
    required this.bundle_uuid,
    required this.cpu_gen,
    required this.features,
    required this.id,
    required this.javafx,
    required this.latest,
    required this.md5_hash,
    required this.os,
    required this.release_status,
    required this.release_type,
    required this.size,
    required this.support_term,
  });

  String get zuluVersion => zuluVersionArray.join(".");

  String get javaVersion => javaVersionArray.join(".");

  factory ZuluData.parse(Map<String, dynamic> json) {
    List jsonZuluVersion = json['zulu_version'];
    List jsonJdkVersion = json['java_version'];
    return ZuluData(
      url: json["url"],
      extension: json['ext'],
      last_modified: DateTime.parse(json['last_modified']),
      name: json['name'],
      javaVersionArray: jsonJdkVersion.cast<int>(),
      sha265_hash: json['sha256_hash'],
      zuluVersionArray: jsonZuluVersion.cast<int>(),
      arch: json['arch'],
      bundle_type: json['bundle_type'],
      abi: json['abi'],
      bundle_uuid: json['bundle_uuid'],
      cpu_gen: (json['cpu_gen'] as List).cast<String>(),
      features: (json['features'] as List).cast<String>(),
      hw_bitness: json['hw_bitness'],
      id: json['id'],
      javafx: json['javafx'],
      latest: json['latest'],
      md5_hash: json['md5_hash'],
      os: json['os'],
      release_status: json['release_status'],
      release_type: json['release_type'],
      size: json['size'],
      support_term: json['support_term'],
    );
  }
}

class Architecture {
  final String zulu;
  final String docker;

  String get dockerFull => "linux/$docker";

  const Architecture._(this.zulu, this.docker);

  static const arm64 = Architecture._("arm", "arm64");
  static const amd64 = Architecture._("x86", "amd64");
}

class OperatingSystem {
  final Architecture arch;
  final String name;
  final int bitness;
  
  const OperatingSystem._(this.name, this.arch, this.bitness);
  
  static const linux_musl_amd64 = OperatingSystem._("linux_musl", Architecture.amd64, 64); // alpine linux
  static const linux_arm64 = OperatingSystem._("linux_glibc", Architecture.arm64, 64);
}

class JavaBundleVersions {
  final String bundleType;
  final String zuluString;

  const JavaBundleVersions._(this.bundleType, this.zuluString);

  static const jdk = JavaBundleVersions._("jdk", "jdk");
  static const jre = JavaBundleVersions._("jre", "headful");

  @override
  String toString() => bundleType;
}