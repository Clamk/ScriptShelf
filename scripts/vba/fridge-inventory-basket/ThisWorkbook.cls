' À coller dans "ThisWorkbook" (éditeur VBA, double-clic sur ThisWorkbook).
' Rien d'autre dans ThisWorkbook.

Private Sub Workbook_Open()
    SurActivationFeuille ActiveSheet        ' si le classeur s'ouvre sur l'onglet Panier
End Sub

Private Sub Workbook_SheetBeforeDoubleClick(ByVal Sh As Object, ByVal Target As Range, Cancel As Boolean)
    GererDoubleClic Sh, Target, Cancel
End Sub

Private Sub Workbook_SheetActivate(ByVal Sh As Object)
    SurActivationFeuille Sh
End Sub
