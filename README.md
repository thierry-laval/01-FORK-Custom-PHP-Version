
# Script pour changer la version de PHP

Bon, pas besoin d'en dire plus quoi, c'est juste un script qui changer la version PHP.

## 1 / Prérequis

Avant de lancer le script, je vous conseille de suivre les recommandations suivantes :

    - AVOIR ACCES AU TERMINAL CPANEL, si cela n'est pas le cas (par exemple sur une lune, vous pouvez contacter le support)

## 2 / Que fait le script ?

Le script va simplement renommé l'ancien .htaccess pour une raison évidente, et en créer un nouveau avec la personnalisation
de la version de PHP.

## 3 / Utilisation

Avant de lancer le script sur le Terminal, il vous faudra savoir le répertoire ou pointe le dossier de votre site, vous pouvez le savoir en vous rendant sur votre cPanel -> Domaine Configurés (pour le cas d'un domaine) ou alors depuis l'outil "Sous-Domaines" (pour le cas d'un sous-domaine) et la section qui vous intéresse est le champ "Racine du document" comme suivant :

![illustration d'exemple](/static/img/racine_du_document.png)

Une fois que vous avez récupéré le répertoire, vous pouvez lancer le script en suivant les étapes suivantes :

    - Vous rendre sur votre cPanel
    - Ouvrir le Terminal de votre cPanel
    - Se rendre dans le répertoire de votre site (cd /home/votre_user/votre_site)

Et ensuite, il faudra lancer les commandes suivantes :

```bash
- wget https://github.com/Shiiigen/customphpversion/releases/download/1.0/phpver.sh
- chmod +x phpver.sh
- ./phpver.sh
```
