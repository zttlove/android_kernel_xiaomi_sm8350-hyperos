import com.diffplug.spotless.LineEnding
import java.util.Properties

plugins {
    alias(libs.plugins.agp.app) apply false
    alias(libs.plugins.agp.test) apply false
    alias(libs.plugins.androidx.baselineprofile) apply false
    alias(libs.plugins.kotlin) apply false
    alias(libs.plugins.compose.compiler) apply false
    alias(libs.plugins.spotless)
}

spotless {
    lineEndings = LineEnding.UNIX

    kotlin {
        target("**/src/**/*.kt")
        targetExclude("**/build/**", "**/generated/**")
        ktlint(libs.versions.ktlint.get())
            .customRuleSets(listOf("io.nlopez.compose.rules:ktlint:${libs.versions.compose.rules.get()}"))
            .editorConfigOverride(
                mapOf(
                    "ktlint_function_naming_ignore_when_annotated_with" to "Composable",
                    "ktlint_compose_modifier-missing-check" to "disabled",
                    "ktlint_compose_compositionlocal-allowlist" to "disabled",
                    "ktlint_compose_mutable-state-param-check" to "disabled",
                    "ktlint_compose_parameter-naming" to "disabled",
                    "ktlint_compose_modifier-naming" to "disabled",
                ),
            )
    }

    kotlinGradle {
        target("**/*.gradle.kts")
        targetExclude("**/build/**", "**/.gradle/**")
        ktlint(libs.versions.ktlint.get())
    }
}

// 源码直接集成时使用上游版本元数据，不能取外层内核仓库的 Git 版本。
val vendoredVersionFile = rootDir.resolve("../resukisu-version")
val vendoredVersion = if (!rootDir.resolve("../.git").exists() && vendoredVersionFile.isFile) {
    Properties().apply {
        vendoredVersionFile.inputStream().use { load(it) }
    }
} else {
    null
}

extra["androidMinSdkVersion"] = 26
extra["androidTargetSdkVersion"] = 37
extra["androidCompileSdkVersion"] = 37
extra["androidBuildToolsVersion"] = "36.1.0"
extra["androidCompileNdkVersion"] = libs.versions.ndk.get()
extra["androidSourceCompatibility"] = JavaVersion.VERSION_21
extra["androidTargetCompatibility"] = JavaVersion.VERSION_21
extra["managerVersionCode"] = 30000 + getGitCommitCount() + 700
extra["managerVersionName"] = getGitDescribe()
extra["isPrBuild"] = project.findProperty("IS_PR_BUILD")?.toString()?.toBoolean() ?: false
extra["defaultManagerPackageName"] = "com.resukisu.resukisu"
extra["managerPackageName"] = project.findProperty("KSU_PACKAGE_NAME")?.toString() ?: extra["defaultManagerPackageName"]
extra["defaultManagerAppName"] = if (extra["isPrBuild"] == true) "BakaSU PR" else "BakaSU"
extra["managerName"] = project.findProperty("KSU_NAME")?.toString() ?: extra["defaultManagerAppName"]

val isSpoofedBuild = project.findProperty("IS_SPOOFED_BUILD")?.toString()?.toBoolean() ?: false

fun getGitCommitCount(): Int {
    if (vendoredVersion != null) {
        return checkNotNull(vendoredVersion.getProperty("COUNT")).toInt()
    }
    return providers.exec {
        commandLine("git", "rev-list", "--count", "HEAD")
    }.standardOutput.asText.get().trim().toInt()
}

fun getGitDescribe(): String {
    val desc = vendoredVersion?.getProperty("TAG") ?: providers.exec {
        commandLine("git", "describe", "--tags", "--always", "--abbrev=0")
    }.standardOutput.asText.get().trim()
    if (isSpoofedBuild) {
        return "$desc-spoofed"
    }
    return desc
}
