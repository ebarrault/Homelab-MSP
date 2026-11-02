# 6. Sauvegardes

## Stratégie

| Quoi | Comment | Fréquence | Rétention |
|---|---|---|---|
| VM serveurs (pfSense, DC01, GLPI, Zabbix) | Proxmox Backup Server, mode *snapshot* (sans arrêt), **déduplication** | chaque nuit à 1 h | 7 jours, 4 semaines, 6 mois |
| VM postes | PBS | dimanche 3 h | 4 semaines |
| État système AD (DC01) | Windows Server Backup (`06-Backup-SystemState.ps1`) | chaque nuit à 23 h 30 | 7 versions |
| Configuration pfSense | export `config.xml` | à chaque modification | historique |
| Copie hors site | *Sync job* PBS vers un second PBS ou un disque USB | hebdomadaire | 4 semaines |

Règle **3-2-1** : 3 copies (production, PBS, copie hors site), 2 supports différents, 1 copie hors du serveur.

## Mise en place

1. Installer PBS sur la VM 130, créer le datastore `labo` sur le second disque (*Administration > Storage/Disks > Directory*).
2. Créer l'utilisateur `backup@pbs` avec le rôle *DatastoreBackup* sur `labo`.
3. Sur PBS : *Prune & GC* (nettoyage quotidien) et **Verify job** hebdomadaire (vérification de l'intégrité des sauvegardes).
4. Sur Proxmox VE :
   ```bash
   PBS_PASSWORD='…' PBS_FINGERPRINT='…' ./scripts/proxmox/backup-jobs.sh
   ```
5. Activer le chiffrement côté client (clé à conserver hors du serveur) si les sauvegardes partent hors site.

## Tests de restauration (à faire et à documenter)

Une sauvegarde n'existe que si sa restauration a été testée.

| Test | Procédure | Résultat attendu |
|---|---|---|
| Restauration complète d'une VM | PBS → restaurer GLPI sous un **nouvel identifiant** (VM 920), réseau débranché | la VM démarre, GLPI répond |
| Restauration d'un fichier | *File Restore* sur la sauvegarde de DC01 → récupérer un fichier du partage | fichier récupéré sans restaurer la VM |
| Objet AD supprimé | supprimer un utilisateur de test puis le restaurer depuis la **corbeille AD** (`Enable-ADOptionalFeature 'Recycle Bin Feature'`) | compte et groupes rétablis |
| Perte du DC | restaurer DC01 depuis PBS dans un réseau isolé | ouverture de session possible |

Durées mesurées (RTO) et âge de la dernière sauvegarde (RPO) consignés dans [tests.md](tests.md).
