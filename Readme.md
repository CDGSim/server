**Pour tester :**

- Installer Docker
- Dans un terminal, aller au dossier source
- Executer la commande :
`docker build -t logserver .` (permet de builder le dossier courant et de tagger l'image avec le nom "logserver")
- Une fois l'image créée, éxecuter :
`docker run -p 8080:8080 logserver`(permet d'executer l'image, en mappant le port 8080 de la machine hote au port 8080 du conteneur)
- Rendez-vous sur http://localhost:8080/ pour voir le résultat

**Comment ça marche ?**

Les routes permettent de définir ce que le serveur doit retourner lorsqu'on appelle une URL. L'essentiel du code se trouve dans le fichier Sources/App/routes.swift
Par exemple, lorsqu'on appelle l'URL racine `/`, c'est le code de la fonction `app.get` (ligne 5) qui est executé. La fonction retourne une vue, c'est à dire du code HTML qui est généré à partir de deux éléments : le template `index.leaf`, et la struct `context` qui est construite en lisant les fichiers sur le disque.
Lorsqu'on appelle l'URL `print/nom_du_fichier_simu`, c'est le code de la fonction `app.get("print", "**")`(ligne 101) qui est executé. La fonction retourne la vue générée à partir du template `print.leaf`.

**Les templates leaf**

Ce sont des fichiers contenant du code HTML, avec des balises qui permettent d'injecter le contexte qu'on leur a passé. C'est assez similaire à la facon dont fonctionnerait un script php.

Pour l'URL racine, le contexte qui est passé au template est la struct suivante :

    struct IndexContext: Encodable {
        struct SimulationIndex: Encodable {
            let name: String
            let group: String
            let path: String
        }

        let simulations: [SimulationIndex]
    }

Elle contient une propriété `simulations` qui est un array de `SimulationIndex`.

Dans le fichier Resources/View/index.leaf :

    #for(simulation in simulations):
        <tr>
            <td>#(simulation.group)</td>
            <td><a href="/print/#(simulation.path)">#(simulation.name)</a></td>
        </tr>
    #endfor
    
permet de générer les lignes du tableau en itérant la constante `simulations`. Pour chaque élément de l'array, on a accès à une struct de type `SimulationIndex`, et on peut donc accéder à ses trois propriétés : `name`, `group` et `path`.
Les lignes avec un `#` sont du code Leaf. La documentation est disponible ici : [https://docs.vapor.codes/4.0/leaf/overview/](https://docs.vapor.codes/4.0/leaf/overview/)

