
name := "nbt2ascii"
organization := "com.infinity88"
version := "1.0.0"
scalaVersion := "2.12.1"

crossPaths := false

resolvers ++= Seq(
  "evil-co" at "http://basket.cindyscats.com/content/repositories/releases/"
)

libraryDependencies ++= Seq(
  "com.evilco.mc" % "nbt" % "1.0.2"
)
