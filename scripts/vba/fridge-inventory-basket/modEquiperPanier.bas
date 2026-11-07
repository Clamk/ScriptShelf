Option Explicit

'==============================================================================
' modEquiperPanier - Alt+F8 > EquiperRacks
'------------------------------------------------------------------------------
' Pose la règle orange sur chaque boîte de chaque feuille "Rack ..." :
' la ligne d'un tube se colore quand sa cellule Panier est remplie.
'
' Quand la lancer
'   - une fois, sur "Rack Modèle", quand ses 8 boîtes sont en place
'   - après avoir copié une BOÎTE à l'intérieur d'une feuille (la copie
'     surveillerait sinon la colonne Panier de la boîte d'origine)
'   Inutile après avoir copié une FEUILLE entière : les règles suivent.
'
' On peut la relancer sans risque : elle retire d'abord ses propres règles
' (fond orange + formule "...<>"""), puis les repose. Les autres mises en forme
' conditionnelles ne sont pas touchées. Les feuilles masquées sont traitées
' aussi (affichées le temps de l'opération, puis masquées à nouveau).
' Une boîte sans en-tête "Panier" ou sans numéros est signalée, pas modifiée.
'==============================================================================

Private Const FOND_PANIER As Long = 10284031   ' orange clair, RGB(255,235,156) : style "Neutre"
Private Const POLICE_PANIER As Long = 22428    ' brun, RGB(156,87,0)

Public Sub EquiperRacks()
    Dim ws As Worksheet, element As Variant, titre As Range, depart As Object
    Dim col As Long, derniere As Long, visibilite As Long
    Dim nbBoites As Long, refus As String, nom As String, racks As String

    If ThisWorkbook.ReadOnly Then
        MsgBox "Le classeur est en lecture seule : rien ne peut être modifié.", vbExclamation, "Équiper"
        Exit Sub
    End If

    Set depart = ActiveSheet
    Application.ScreenUpdating = False
    On Error GoTo Erreur

    For Each ws In ThisWorkbook.Worksheets
        If EstRack(ws) Then
            racks = racks & IIf(racks = "", "", ", ") & ws.Name
            visibilite = ws.Visible
            ws.Visible = xlSheetVisible         ' une feuille masquée ne peut pas être activée
            RetirerReglesOrange ws
            For Each element In TitresDeBoites(ws)
                Set titre = element
                nom = ws.Name & " - " & titre.Cells(1, 1).Text
                col = ColonnePanier(titre)
                derniere = DerniereLigne(titre)

                If col = 0 Then
                    refus = refus & vbCrLf & "  " & nom & " : pas d'en-tête ""Panier"""
                ElseIf derniere <= titre.Row + 1 Then
                    refus = refus & vbCrLf & "  " & nom & " : aucun emplacement numéroté sous les en-têtes"
                Else
                    PoserRegleOrange ws.Range(ws.Cells(titre.Row + 2, titre.Column), ws.Cells(derniere, col)), col
                    nbBoites = nbBoites + 1
                End If
            Next element
            ws.Visible = visibilite
        End If
    Next ws

    depart.Activate
    Application.ScreenUpdating = True
    If racks = "" Then
        MsgBox "Aucune feuille dont le nom commence par ""Rack"".", vbExclamation, "Équiper"
        Exit Sub
    End If
    ConstruirePanier                        ' crée la feuille Panier si besoin

    MsgBox "Feuilles traitées : " & racks & vbCrLf & vbCrLf & _
           "Boîtes équipées : " & nbBoites & _
           IIf(refus = "", "", vbCrLf & vbCrLf & "Non traitées (à vérifier) :" & refus), _
           IIf(refus = "", vbInformation, vbExclamation), "Équiper"
    Exit Sub

Erreur:
    nom = "": If Not ws Is Nothing Then nom = " (feuille " & ws.Name & ")": ws.Visible = visibilite
    Application.ScreenUpdating = True
    MsgBox "Équipement interrompu" & nom & " : " & Err.Description & vbCrLf & _
           "Feuille protégée ? Corriger, puis relancer EquiperRacks.", vbCritical, "Équiper"
End Sub

'------------------------------------------------------------------------------
' Retire de la feuille les règles posées par cette macro, pour pouvoir les
' reposer sans doublon. Signature : formule, fond orange ET texte brun.
'------------------------------------------------------------------------------
Private Sub RetirerReglesOrange(ByVal ws As Worksheet)
    Dim i As Long, fc As Object
    For i = ws.Cells.FormatConditions.Count To 1 Step -1
        Set fc = ws.Cells.FormatConditions(i)
        If fc.Type = xlExpression Then
            If fc.Interior.Color = FOND_PANIER And fc.Font.Color = POLICE_PANIER And _
               fc.Formula1 Like "=*<>""""" Then fc.Delete
        End If
    Next i
End Sub

'------------------------------------------------------------------------------
' Règle de mise en forme conditionnelle : orange si la cellule Panier
' de la même ligne n'est pas vide
'------------------------------------------------------------------------------
Private Sub PoserRegleOrange(ByVal plage As Range, ByVal col As Long)
    Dim fc As FormatCondition

    ' Formule du type =$I3<>"" : colonne figée ($), ligne relative.
    ' Excel lit une formule relative depuis la cellule active : on se place
    ' donc sur la 1re cellule de la plage avant de créer la règle.
    plage.Worksheet.Activate
    plage.Cells(1, 1).Select

    Set fc = plage.FormatConditions.Add(Type:=xlExpression, _
        Formula1:="=" & plage.Worksheet.Cells(plage.Row, col).Address(RowAbsolute:=False) & "<>""""")
    fc.SetFirstPriority
    fc.Interior.Color = FOND_PANIER
    fc.Font.Color = POLICE_PANIER
End Sub
