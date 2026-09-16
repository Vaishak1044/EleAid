allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Keep Flutter plugins on matching JVM targets. record_android uses Java 17,
// while tflite_flutter 0.12.1 targets Java 11.
subprojects {
    configurations.configureEach {
        // The app uses the CPU interpreter. The optional LiteRT GPU artifact
        // brings legacy implied storage/phone permissions into the manifest.
        exclude(group = "com.google.ai.edge.litert", module = "litert-gpu")
        exclude(group = "com.google.ai.edge.litert", module = "litert-gpu-api")
    }

    afterEvaluate {
        val isTflitePlugin = name == "tflite_flutter"
        tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
            sourceCompatibility = if (isTflitePlugin) "11" else "17"
            targetCompatibility = if (isTflitePlugin) "11" else "17"
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(
                    if (isTflitePlugin) {
                        org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
                    } else {
                        org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                    }
                )
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
