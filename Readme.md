**Pour tester :**
- Installer Docker
- Dans un terminal, aller au dossier source
- Executer la commande :
`docker build -t logserver .` (permet de builder le dossier courant et de tagger l'image avec le nom "logserver")
- Une fois l'image créée, éxecuter :
`docker run -p 8080:8080 logserver`(permet d'executer l'image, en mappant le port 8080 de la machine hote au port 8080 du conteneur)
- Rendez-vous sur http://localhost:8080/ pour voir le résultat

