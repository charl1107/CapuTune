allprojects {
    repositories {
        google()
        mavenCentral()
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

// Some Flutter plugins (e.g. file_picker) declare a compileSdk older than what
// their transitive Android dependencies require. AGP 9 fails the AAR metadata
// check in that case, so align every Android module with the app's
// compileSdk (flutter.compileSdkVersion). Registering an afterEvaluate hook
// ensures this wins over the value each plugin sets in its own build script.
subprojects {
    fun alignCompileSdk() {
        extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)?.compileSdk = 36
        extensions.findByType(com.android.build.api.dsl.ApplicationExtension::class.java)?.compileSdk = 36
    }

    if (state.executed) {
        alignCompileSdk()
    } else {
        afterEvaluate { alignCompileSdk() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
