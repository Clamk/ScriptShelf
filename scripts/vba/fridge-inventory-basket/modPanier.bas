Option Explicit
Option Private Module

'==============================================================================
' modPanier v2 - Mise au panier d'un tube par double-clic sur son emplacement
'------------------------------------------------------------------------------
' Principe : le statut d'un tube vit dans sa propre ligne
'   Chaque boîte a une colonne d'en-tête "Panier" (dernière colonne de la boîte).
'     - vide   : le tube est en place
'     - coche  : le tube est au panier (qui et quand sont notés dans l'Archive)
'   Tout le reste en découle, rien d'autre n'est à synchroniser :
'     - la couleur orange vient d'une mise en forme conditionnelle
'     - la feuille "Panier" est une vue, reconstruite à chaque ouverture
'     - la feuille "Archive" garde la trace de chaque action
'
' Double-clic sur un numéro d'emplacement (1re colonne d'une boîte)
'     tube présent, pas au panier -> confirmation, puis mise au panier
'     tube au panier              -> Oui : sorti (emplacement vidé)
'                                    Non : remis en place (retiré du panier)
'                                    Annuler : rien
'     emplacement vide            -> simple message
'     vide mais marqué au panier  -> proposition d'effacer le marqueur
'   Ailleurs dans la boîte, le double-clic garde son effet normal (édition).
' Double-clic sur une ligne de la feuille Panier -> saut vers le tube
'
' Feuilles concernées : seulement celles dont le nom commence par "Rack"
'   (Rack 1, Rack 2, ...). Les autres (ex. "Réception-n° lot") ne sont jamais
'   lues ni modifiées, et le double-clic y garde son effet normal.
'
' Structure attendue d'une boîte (n'importe où dans une feuille Rack)
'   ligne titre    : cellule fusionnée sur la largeur de la boîte, "Box ..."
'   ligne suivante : en-têtes Emplacement, Cells, ..., Supp info, Panier
'   lignes suivantes : un emplacement par ligne, numéro dans la 1re colonne
'   La boîte est retrouvée à partir de la cellule cliquée (titre fusionné
'   au-dessus), la colonne Panier par son en-tête : aucun numéro de colonne
'   n'est fixé dans le code. C'est la structure de la feuille "Rack Modèle".
'
' Couleur orange : posée par la macro EquiperRacks (module modEquiperPanier).
'==============================================================================

' --- Réglages : feuilles -------------------------------------------------------
Private Const FEUILLE_PANIER As String = "Panier"
Private Const FEUILLE_ARCHIVE As String = "Archive"
Private Const PREFIXE_RACK As String = "Rack"     ' début du nom des feuilles d'inventaire

' --- Réglages : structure des boîtes ------------------------------------------
Private Const PREFIXE_BOITE As String = "Box"     ' début du titre fusionné
Private Const ENTETE_STATUT As String = "Panier"  ' en-tête de la colonne de statut
Private Const ACTION_PANIER As String = "Mis au panier"   ' action notée dans l'Archive
Private Const MAX_EMPLACEMENTS As Long = 400       ' plafond de recherche (> 81)

' Position des champs, comptée depuis la colonne Emplacement (= 0)
Private Const CH_CELLS As Long = 1      ' Cells
Private Const CH_PASSAGE As Long = 2    ' Passage
Private Const CH_DATE As Long = 4       ' Freezing date
Private Const NB_CHAMPS As Long = 7     ' Cells ... Supp info, recopiés à l'Archive

' --- Réglages : colonnes de la feuille Panier ---------------------------------
Private Const P_FEUILLE As Long = 1
Private Const P_ADRESSE As Long = 8     ' technique, masquée : où sauter

'==============================================================================
' 1. POINTS D'ENTRÉE (appelés par ThisWorkbook et par EquiperRacks)
'==============================================================================

'------------------------------------------------------------------------------
' Double-clic n'importe où dans le classeur
'------------------------------------------------------------------------------
Public Sub GererDoubleClic(ByVal Sh As Object, ByVal Target As Range, ByRef Cancel As Boolean)
    Dim ws As Worksheet, cible As Range, titre As Range
    Dim contenu As Range, statut As Range
    Dim lieu As String, recap As String, qui As String, vide As Boolean, col As Long

    ' 1. Aiguillage selon la feuille
    If TypeName(Sh) <> "Worksheet" Then Exit Sub
    Set ws = Sh
    If ws.Name = FEUILLE_PANIER Then
        AllerAuTube ws, Target, Cancel
        Exit Sub
    End If
    If Not EstRack(ws) Then Exit Sub                ' Archive, Réception... : rien

    ' 2. Garde-fous : un numéro d'emplacement, dans la 1re colonne d'une boîte
    Set cible = Target.Cells(1, 1)
    If IsEmpty(cible.Value) Or Not IsNumeric(cible.Value) Then Exit Sub
    Set titre = TrouverTitre(cible)
    If titre Is Nothing Then Exit Sub
    If cible.Column <> titre.Column Then Exit Sub   ' autre colonne : édition normale
    If cible.Row <= titre.Row + 1 Then Exit Sub     ' titre ou en-têtes

    Cancel = True                                   ' on prend la main

    If ThisWorkbook.ReadOnly Then
        MsgBox "Le classeur est ouvert en lecture seule " & _
               "(sans doute déjà ouvert par quelqu'un d'autre)." & vbCrLf & _
               "Rien ne serait enregistré : réessayer plus tard.", vbExclamation, "Panier"
        Exit Sub
    End If

    col = ColonnePanier(titre)
    If col = 0 Then
        MsgBox "Pas de colonne """ & ENTETE_STATUT & """ dans " & titre.Cells(1, 1).Text & "." & vbCrLf & _
               "Vérifier les en-têtes de la boîte (voir Rack Modèle).", vbExclamation, "Panier"
        Exit Sub
    End If
    Set statut = ws.Cells(cible.Row, col)
    Set contenu = ws.Range(cible.Offset(0, 1), statut.Offset(0, -1))
    vide = (Application.WorksheetFunction.CountA(contenu) = 0)

    lieu = ws.Name & " - " & titre.Cells(1, 1).Text & " - emplacement " & cible.Text
    recap = lieu & vbCrLf & _
            cible.Offset(0, CH_CELLS).Text & ", " & cible.Offset(0, CH_PASSAGE).Text & _
            ", congelé le " & cible.Offset(0, CH_DATE).Text

    ' À partir d'ici, toute erreur affiche un message clair.
    ' L'Archive est toujours écrite AVANT de modifier l'inventaire.
    On Error GoTo Erreur

    If Trim$(statut.Text) = "" Then
        ' 3. Pas au panier
        If vide Then
            MsgBox lieu & " est vide.", vbInformation, "Panier"
        ElseIf MsgBox("Mettre au panier ?" & vbCrLf & vbCrLf & recap, _
                      vbYesNo + vbQuestion, "Panier") = vbYes Then
            Archiver ACTION_PANIER, ws, titre, cible, contenu
            statut.Value = ChrW$(&H2713)            ' coche (caractère Unicode 2713)
        End If
        Exit Sub
    End If

    qui = InfoPanier(ws.Name, titre.Cells(1, 1).Text, cible.Text)
    If vide Then
        ' 4. Marqué au panier, mais l'emplacement a été vidé à la main
        If MsgBox(lieu & " est vide mais marqué au panier (" & qui & ")." & _
                  vbCrLf & vbCrLf & "Effacer le marqueur ?", _
                  vbYesNo + vbQuestion, "Panier") = vbYes Then
            Archiver "Marqueur effacé", ws, titre, cible, contenu
            statut.ClearContents
        End If

    Else
        ' 5. Au panier : sortie, remise en place, ou rien
        Select Case MsgBox(recap & vbCrLf & "Au panier : " & qui & vbCrLf & vbCrLf & _
                           "Oui : tube sorti, vider l'emplacement" & vbCrLf & _
                           "Non : remettre en place (retirer du panier)" & vbCrLf & _
                           "Annuler : ne rien faire", _
                           vbYesNoCancel + vbQuestion, "Panier")
            Case vbYes
                Archiver "Sorti", ws, titre, cible, contenu
                contenu.ClearContents       ' contenu seulement : la mise en forme reste
                statut.ClearContents
            Case vbNo
                Archiver "Remis en place", ws, titre, cible, contenu
                statut.ClearContents
        End Select
    End If
    Exit Sub

Erreur:
    MsgBox "Action interrompue : " & Err.Description & vbCrLf & vbCrLf & _
           "Vérifier " & lieu & vbCrLf & "et la dernière ligne de l'Archive.", _
           vbCritical, "Panier"
End Sub

'------------------------------------------------------------------------------
' Activation d'une feuille (et ouverture du classeur) : la vue Panier est
' reconstruite. La consulter ne compte pas comme une modification.
'------------------------------------------------------------------------------
Public Sub SurActivationFeuille(ByVal Sh As Object)
    Dim etaitEnregistre As Boolean
    If Sh.Name <> FEUILLE_PANIER Then Exit Sub
    etaitEnregistre = ThisWorkbook.Saved
    ConstruirePanier
    ThisWorkbook.Saved = etaitEnregistre
End Sub

'==============================================================================
' 2. ACTIONS
'==============================================================================

'------------------------------------------------------------------------------
' Reconstruit la feuille Panier : tous les tubes dont la colonne Panier
' est remplie, dans toutes les feuilles Rack
'------------------------------------------------------------------------------
Public Sub ConstruirePanier()
    Dim p As Worksheet, ws As Worksheet, element As Variant, titre As Range
    Dim statuts As Range, c As Range, col As Long, n As Long

    On Error GoTo Erreur
    Application.ScreenUpdating = False

    Set p = ObtenirFeuille(FEUILLE_PANIER, EntetesPanier())
    p.Cells.ClearContents
    p.Range("A:H").NumberFormat = "@"       ' valeurs recopiées telles qu'affichées
    p.Range("A1:H1").Value = EntetesPanier()
    n = 1

    For Each ws In ThisWorkbook.Worksheets
        If EstRack(ws) Then
            For Each element In TitresDeBoites(ws)
                Set titre = element
                Set statuts = ColonneStatut(titre)
                ' Une boîte sans aucun tube au panier coûte un seul appel
                If Not statuts Is Nothing Then
                    If Application.WorksheetFunction.CountA(statuts) > 0 Then
                        col = titre.Column
                        For Each c In statuts.Cells
                            If Trim$(c.Text) <> "" Then
                                n = n + 1
                                p.Cells(n, 1).Resize(1, 8).Value = Array( _
                                    ws.Name, titre.Cells(1, 1).Text, _
                                    ws.Cells(c.Row, col).Text, _
                                    ws.Cells(c.Row, col + CH_CELLS).Text, _
                                    ws.Cells(c.Row, col + CH_PASSAGE).Text, _
                                    ws.Cells(c.Row, col + CH_DATE).Text, _
                                    InfoPanier(ws.Name, titre.Cells(1, 1).Text, ws.Cells(c.Row, col).Text), _
                                    ws.Cells(c.Row, col).Address)
                            End If
                        Next c
                    End If
                End If
            Next element
        End If
    Next ws

    p.Range("A:G").EntireColumn.AutoFit
    p.Columns(P_ADRESSE).Hidden = True
    Application.ScreenUpdating = True
    Exit Sub

Erreur:
    Application.ScreenUpdating = True
    MsgBox "Le Panier n'a pas pu être mis à jour : " & Err.Description, vbExclamation, "Panier"
End Sub

'------------------------------------------------------------------------------
' Double-clic dans la feuille Panier : saute vers le tube dans l'inventaire
'------------------------------------------------------------------------------
Private Sub AllerAuTube(ByVal p As Worksheet, ByVal Target As Range, ByRef Cancel As Boolean)
    Dim ws As Worksheet, adresse As String

    If Target.Row < 2 Then Exit Sub
    adresse = CStr(p.Cells(Target.Row, P_ADRESSE).Value)
    If adresse = "" Then Exit Sub
    Cancel = True

    On Error Resume Next
    Set ws = ThisWorkbook.Worksheets(CStr(p.Cells(Target.Row, P_FEUILLE).Value))
    On Error GoTo 0
    If ws Is Nothing Then Exit Sub
    If ws.Visible <> xlSheetVisible Then
        MsgBox "La feuille " & ws.Name & " est masquée : l'afficher pour aller au tube.", vbInformation, "Panier"
        Exit Sub
    End If
    Application.Goto ws.Range(adresse), True
End Sub

'------------------------------------------------------------------------------
' Ajoute une ligne à l'Archive (écrite d'un seul bloc) :
' quand, qui, quoi, où, le contenu du tube
'------------------------------------------------------------------------------
Private Sub Archiver(ByVal action As String, ByVal ws As Worksheet, ByVal titre As Range, _
                     ByVal cible As Range, ByVal contenu As Range)
    Dim a As Worksheet, ligne As Range, v() As Variant, i As Long

    Set a = ObtenirFeuille(FEUILLE_ARCHIVE, EntetesArchive())
    Set ligne = a.Cells(a.Cells(a.Rows.Count, 1).End(xlUp).Row + 1, 1).Resize(1, 6 + NB_CHAMPS)

    ReDim v(1 To 1, 1 To 6 + NB_CHAMPS)
    v(1, 1) = Now
    v(1, 2) = NomUtilisateur()
    v(1, 3) = action
    v(1, 4) = ws.Name
    v(1, 5) = titre.Cells(1, 1).Text
    v(1, 6) = cible.Text
    For i = 1 To NB_CHAMPS
        If i <= contenu.Columns.Count Then v(1, 6 + i) = contenu.Cells(1, i).Text
    Next i

    ' Format texte : valeurs recopiées telles qu'affichées
    ' (évite qu'Excel réinterprète "01.06.2023" ou "1,2M")
    ligne.NumberFormat = "@"
    ligne.Cells(1, 1).NumberFormat = "dd.mm.yyyy hh:mm"
    ligne.Value = v
End Sub

'------------------------------------------------------------------------------
' Qui a mis ce tube au panier, et quand : la dernière ligne "Mis au panier"
' de l'Archive pour cet emplacement (Archive lue d'un bloc)
'------------------------------------------------------------------------------
Private Function InfoPanier(ByVal feuille As String, ByVal boite As String, ByVal empl As String) As String
    Dim a As Worksheet, v As Variant, i As Long, n As Long

    InfoPanier = "origine inconnue"
    On Error Resume Next
    Set a = ThisWorkbook.Worksheets(FEUILLE_ARCHIVE)
    On Error GoTo 0
    If a Is Nothing Then Exit Function
    n = a.Cells(a.Rows.Count, 1).End(xlUp).Row
    If n < 2 Then Exit Function

    v = a.Range(a.Cells(2, 1), a.Cells(n, 6)).Value     ' Date, Par, Action, Feuille, Boîte, Empl.
    For i = UBound(v, 1) To 1 Step -1                   ' du plus récent au plus ancien
        If CStr(v(i, 3)) = ACTION_PANIER And CStr(v(i, 4)) = feuille And _
           CStr(v(i, 5)) = boite And CStr(v(i, 6)) = empl Then
            InfoPanier = v(i, 2) & " - " & Format$(v(i, 1), "dd\.mm\.yyyy hh:mm")
            Exit Function
        End If
    Next i
End Function

'==============================================================================
' 3. OUTILS (EstRack, TitresDeBoites, ColonnePanier et DerniereLigne servent
'    aussi à EquiperRacks)
'==============================================================================

'------------------------------------------------------------------------------
' Remonte la colonne depuis la cellule jusqu'au titre "Box ..." fusionné.
' Renvoie la zone fusionnée entière (sa largeur = celle de la boîte),
' ou Nothing si aucun titre n'est trouvé. La recherche s'arrête à la hauteur
' maximale d'une boîte : un clic loin de toute boîte reste instantané.
'------------------------------------------------------------------------------
Private Function TrouverTitre(ByVal cellule As Range) As Range
    Dim r As Long, haut As Long, c As Range
    haut = cellule.Row - MAX_EMPLACEMENTS - 2
    If haut < 1 Then haut = 1
    For r = cellule.Row - 1 To haut Step -1
        Set c = cellule.Worksheet.Cells(r, cellule.Column)
        If c.MergeCells Then
            If CommencePar(c.MergeArea.Cells(1, 1).Text, PREFIXE_BOITE) Then
                Set TrouverTitre = c.MergeArea
                Exit Function
            End If
        End If
    Next r
End Function

'------------------------------------------------------------------------------
' Liste tous les titres de boîtes (zones fusionnées "Box ...") d'une feuille
'------------------------------------------------------------------------------
Public Function TitresDeBoites(ByVal ws As Worksheet) As Collection
    Dim res As Collection, zone As Range, v As Variant, i As Long, k As Long

    Set res = New Collection
    Set zone = ZoneRemplie(ws)
    If Not zone Is Nothing Then
        v = zone.Value                      ' lecture d'un bloc : rapide
        If IsArray(v) Then
            For i = 1 To UBound(v, 1)
                For k = 1 To UBound(v, 2)
                    If VarType(v(i, k)) = vbString Then
                        If CommencePar(v(i, k), PREFIXE_BOITE) Then
                            If zone.Cells(i, k).MergeCells Then res.Add zone.Cells(i, k).MergeArea
                        End If
                    End If
                Next k
            Next i
        End If
    End If
    Set TitresDeBoites = res
End Function

'------------------------------------------------------------------------------
' Cellules de statut d'une boîte (une par emplacement), ou Nothing si
' la boîte n'a pas d'en-tête "Panier" ou aucun emplacement
'------------------------------------------------------------------------------
Private Function ColonneStatut(ByVal titre As Range) As Range
    Dim ws As Worksheet, col As Long, derniere As Long
    Set ws = titre.Worksheet
    col = ColonnePanier(titre)
    derniere = DerniereLigne(titre)
    If col > 0 And derniere > titre.Row + 1 Then
        Set ColonneStatut = ws.Range(ws.Cells(titre.Row + 2, col), ws.Cells(derniere, col))
    End If
End Function

'------------------------------------------------------------------------------
' Colonne "Panier" d'une boîte, repérée par son en-tête dans la ligne sous le
' titre (sur la largeur du titre et la colonne juste après). 0 si absente.
'------------------------------------------------------------------------------
Public Function ColonnePanier(ByVal titre As Range) As Long
    Dim col As Long
    For col = titre.Column + 1 To titre.Column + titre.Columns.Count
        If StrComp(Trim$(titre.Worksheet.Cells(titre.Row + 1, col).Text), ENTETE_STATUT, vbTextCompare) = 0 Then
            ColonnePanier = col
            Exit Function
        End If
    Next col
End Function

'------------------------------------------------------------------------------
' Dernière ligne d'emplacement d'une boîte : sous les en-têtes, tant que la
' 1re colonne contient un numéro. Renvoie la ligne des en-têtes s'il n'y en a
' aucun. La colonne est lue d'un bloc.
'------------------------------------------------------------------------------
Public Function DerniereLigne(ByVal titre As Range) As Long
    Dim v As Variant, i As Long
    v = titre.Worksheet.Cells(titre.Row + 2, titre.Column).Resize(MAX_EMPLACEMENTS, 1).Value
    For i = 1 To MAX_EMPLACEMENTS
        If IsEmpty(v(i, 1)) Or Not IsNumeric(v(i, 1)) Then Exit For
    Next i
    DerniereLigne = titre.Row + i
End Function

'------------------------------------------------------------------------------
' Vrai si la feuille est un inventaire (nom commençant par "Rack")
'------------------------------------------------------------------------------
Public Function EstRack(ByVal ws As Worksheet) As Boolean
    EstRack = CommencePar(ws.Name, PREFIXE_RACK)
End Function

'------------------------------------------------------------------------------
' Vrai si le texte commence par le préfixe (espaces et majuscules ignorés)
'------------------------------------------------------------------------------
Private Function CommencePar(ByVal txt As String, ByVal prefixe As String) As Boolean
    CommencePar = (StrComp(Left$(Trim$(txt), Len(prefixe)), prefixe, vbTextCompare) = 0)
End Function

'------------------------------------------------------------------------------
' De A1 à la dernière cellule réellement remplie. (UsedRange inclut aussi les
' cellules seulement mises en forme, parfois jusqu'à la ligne 1 048 576.)
' Excel retient les options du dernier Find pour le Ctrl+F de l'utilisateur :
' la recherche "par lignes" passe donc en dernier, c'est le réglage habituel.
'------------------------------------------------------------------------------
Private Function ZoneRemplie(ByVal ws As Worksheet) As Range
    Dim derCol As Range, derLigne As Range
    Set derCol = ws.Cells.Find("*", LookIn:=xlFormulas, LookAt:=xlPart, _
                               SearchOrder:=xlByColumns, SearchDirection:=xlPrevious)
    If derCol Is Nothing Then Exit Function
    Set derLigne = ws.Cells.Find("*", LookIn:=xlFormulas, LookAt:=xlPart, _
                                 SearchOrder:=xlByRows, SearchDirection:=xlPrevious)
    Set ZoneRemplie = ws.Range(ws.Cells(1, 1), ws.Cells(derLigne.Row, derCol.Column))
End Function

'------------------------------------------------------------------------------
' Renvoie la feuille demandée ; la crée (avec en-têtes) si elle n'existe pas,
' sans quitter la feuille où l'on se trouve
'------------------------------------------------------------------------------
Private Function ObtenirFeuille(ByVal nom As String, ByVal entetes As Variant) As Worksheet
    Dim f As Worksheet, depart As Object, evenements As Boolean
    Dim numErr As Long, descErr As String

    On Error Resume Next
    Set f = ThisWorkbook.Worksheets(nom)
    On Error GoTo 0
    If Not f Is Nothing Then
        Set ObtenirFeuille = f
        Exit Function
    End If

    Set depart = ActiveSheet
    evenements = Application.EnableEvents
    Application.EnableEvents = False        ' évite de relancer SurActivationFeuille
    On Error GoTo Echec

    Set f = ThisWorkbook.Worksheets.Add(After:=ThisWorkbook.Worksheets(ThisWorkbook.Worksheets.Count))
    f.Name = nom
    f.Range("A1").Resize(1, UBound(entetes) - LBound(entetes) + 1).Value = entetes
    f.Rows(1).Font.Bold = True
    If Not depart Is Nothing Then depart.Activate

    Application.EnableEvents = evenements
    Set ObtenirFeuille = f
    Exit Function

Echec:
    numErr = Err.Number: descErr = Err.Description
    Application.EnableEvents = evenements   ' toujours rétablir les événements
    Err.Raise numErr, , descErr
End Function

'------------------------------------------------------------------------------
' Nom de l'utilisateur : nom saisi dans Office, sinon session Windows
'------------------------------------------------------------------------------
Private Function NomUtilisateur() As String
    NomUtilisateur = Trim$(Application.UserName)
    If NomUtilisateur = "" Then NomUtilisateur = Environ$("USERNAME")
End Function

Private Function EntetesPanier() As Variant
    EntetesPanier = Array("Feuille", "Boîte", "Emplacement", "Cells", "Passage", _
                          "Freezing date", "Au panier (par - le)", "Adresse (technique)")
End Function

Private Function EntetesArchive() As Variant
    EntetesArchive = Array("Date", "Par", "Action", "Feuille", "Boîte", "Emplacement", _
                           "Cells", "Passage", "Nb cells", "Freezing date", "Freezing medium", _
                           "Culture medium", "Supp info")
End Function
