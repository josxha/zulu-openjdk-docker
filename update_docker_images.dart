import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart';

const JAVA_LTS_VERSION = 17; // arm64 builds only available for openjdk17
const HARDWARE_BITNESS = 64; // only builds for 64bit
// headless version not available for arm64
// https://docs.azul.com/core/zulu-openjdk/supported-platforms
const List<JavaBundleVersions> JAVA_BUNDLE_VERSIONS = [JavaBundleVersions.jre, JavaBundleVersions.jdk];
const OS_ARCHITECTURES = [Architectures.x86_64, Architectures.arm64];
const DOCKER_TAG_API = "https://registry.hub.docker.com/v1/repositories/josxha/zulu-openjdk/tags";

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
    String? versionTag;
    Map<Architectures, ZuluData> data = {};
    for (var arch in OS_ARCHITECTURES) {
      var zuluData = await getZuluData(
        features: javaBundleVersion.zuluString,
        arch: arch.zulu,
      );
      data[arch] = zuluData;

      print("[${javaBundleVersion.bundleType}-$JAVA_LTS_VERSION] Check if the docker image for ${javaBundleVersion.bundleType} needs to get updated...");
      versionTag = "${javaBundleVersion.bundleType}-$JAVA_LTS_VERSION-${zuluData.zuluVersion}";
      if (dockerImageTags.contains(versionTag)) {
        // image already exists
        if (FORCE_BUILDS) {
          print("[$versionTag] Image exists but force update enabled.");
        } else {
          print("[$versionTag] Image exists, skip build.");
          continue;
        }
      }

      // image doesn't exist yet
      print("[$versionTag] Build and push image");
      // download openJDK archives
      var response = await get(Uri.parse(data[arch]!.url));
      if (response.statusCode != 200)
        throw "Couldn't download ${zuluData.name}\n${response.body}";
      await File("openjdk-${arch.docker}.tar.gz").writeAsBytes(response.bodyBytes);
    }

    // test if the version numbers are the same for every arch
    var first = data[OS_ARCHITECTURES.first];
    for (var arch in OS_ARCHITECTURES.sublist(1)) {
      if (data[arch]?.zuluVersion != first?.zuluVersion)
        throw "Error, zulu version mismatch ('${first?.zuluVersion}' and '${data[arch]?.zuluVersion}')!";
    }
    var tags = [
      "${javaBundleVersion.bundleType}-$JAVA_LTS_VERSION",
      "latest",
      javaBundleVersion.bundleType,
      versionTag!,
    ];
    await dockerBuildPushRemove(tags);
    print("[$versionTag] Built, pushed and cleaned up successfully!");
  }
}

/// Data object for the zulu api response
/// Azul API documentation:
/// https://app.swaggerhub.com/domains-docs/azul/zulu-download-api-shared/1.0#/components/pathitems/Bundles/get
Future<ZuluData> getZuluData({required String features, required String arch, int java_version = JAVA_LTS_VERSION, int hw_bitness = HARDWARE_BITNESS}) async {
  // Example url:
  // https://api.azul.com/zulu/download/community/v1.0/bundles/latest/?os=linux_musl&arch=arm&hw_bitness=64&bundle_type=jre&ext=&java_version=17&features=headfull
  var uri = Uri(
    scheme: "https",
    host: "api.azul.com",
    path: "zulu/download/community/v1.0/bundles/latest",
    queryParameters: {
      "os": "linux_musl", // alpine linux
      "arch": arch,
      "hw_bitness": hw_bitness.toString(),
      "java_version": java_version.toString(),
      "features": features,
    },
  );
  //print(uri);
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

Future<void> dockerBuildPushRemove(List<String> tags) async {
  var args = [
    "buildx", "build", ".",
    DRY_RUN ? "--load" : "--push",
    "--platform",
  ];
  args.add(OS_ARCHITECTURES.map((var arch) => arch.dockerFull).toList().join(","));
  for (var tag in tags) {
    args.addAll([
      "--tag",
      "josxha/zulu-openjdk:$tag",
    ]);
  }
  if (DRY_RUN)
    return;
  var taskResult = Process.runSync("docker", args);
  if (taskResult.exitCode != 0) {
    print(taskResult.stdout);
    print(taskResult.stderr);
    throw Exception("Couldn't run docker build for $tags.");
  }
}

Future<List<String>> getDockerImageTags() async {
  var response = await get(Uri.parse(DOCKER_TAG_API));
  var jsonList = jsonDecode(response.body) as List;
  return jsonList.map((listElement) => listElement["name"] as String).toList();
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

class Architectures {
  final String zulu;
  final String docker;

  String get dockerFull => "linux/$docker";

  const Architectures._(this.zulu, this.docker);

  static const arm64 = Architectures._("arm", "arm64");
  static const x86_64 = Architectures._("x86", "amd64");
}

class JavaBundleVersions {
  final String bundleType;
  final String zuluString;

  const JavaBundleVersions._(this.bundleType, this.zuluString);

  static const jdk = Architectures._("jdk", "jdk");
  static const jre = Architectures._("jdk", "headful");

  @override
  String toString() => bundleType;
}

