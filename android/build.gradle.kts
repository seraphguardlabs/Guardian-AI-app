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

    afterEvaluate {
        val project = this
        if (project.extensions.findByName("android") != null) {
            try {
                project.extensions.configure<com.android.build.gradle.BaseExtension>("android") {
                    if (namespace == null) {
                        val manifest = file("src/main/AndroidManifest.xml")
                        if (manifest.exists()) {
                            val content = manifest.readText()
                            val regex = "package=\"([^\"]+)\"".toRegex()
                            val match = regex.find(content)
                            if (match != null) {
                                namespace = match.groupValues[1]
                                println("Auto-assigned namespace '$namespace' to project '${project.name}'")
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                // Ignore
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
