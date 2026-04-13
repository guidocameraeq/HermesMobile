# Keep jTDS JDBC driver classes (used by sql_conn)
-keep class net.sourceforge.jtds.** { *; }
-dontwarn net.sourceforge.jtds.**

# Keep JDBC driver manager
-keep class java.sql.** { *; }
-dontwarn java.sql.**
-dontwarn javax.sql.**
-dontwarn javax.naming.**
