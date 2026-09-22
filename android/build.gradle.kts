allprojects {
    repositories {
        google()
        mavenCentral()
        // Only present once android/unityLibrary is a real Gradle module
        // (see settings.gradle.kts) — it holds unityLibrary's own .jar/.aar
        // dependencies under libs/.
        val unityLibraryProject = rootProject.findProject(":unityLibrary")
        if (unityLibraryProject != null) {
            flatDir {
                dirs("${unityLibraryProject.projectDir}/libs")
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
